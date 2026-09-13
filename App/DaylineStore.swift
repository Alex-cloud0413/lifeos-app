import Foundation
import SwiftData
import SwiftUI
import CloudKit
import CoreData
import UserNotifications

@Model final class SyncEvent {
    var logicalID: String = ""
    var payload: Data = Data()
    var schema: Int = 1
    init(event: ChangeEvent) throws {
        logicalID = event.id
        payload = try JSONEncoder().encode(event)
    }
}

@MainActor @Observable final class DaylineStore {
    static let shared = DaylineStore()
    private(set) var projection = Projection()
    private(set) var events: [ChangeEvent] = []
    private(set) var container: ModelContainer?
    var errorMessage: String?
    var syncStatus = "正在检查 iCloud…"
    var lastImport: Date?
    var lastExport: Date?
    var cloudAvailable = false
    var cloudDiagnostics = ""
    var agentStatus = "未开启"
    var ready = false
    let cloudEnabled: Bool
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    @ObservationIgnored private var eventIndex = EventIndex()
    private let actorID: String
    #if os(macOS)
    private var server: AgentServer?
    #endif

    init() {
        #if DAYLINE_LOCAL
        cloudEnabled = false
        #else
        cloudEnabled = true
        #endif
        // Clear this app's old reminders without requesting notification permission.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        let stored = UserDefaults.standard.string(forKey: "deviceActor") ?? UUID().uuidString
        actorID = stored; UserDefaults.standard.set(stored, forKey: "deviceActor")
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LifeOS", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeURL = directory.appendingPathComponent(cloudEnabled ? "Cloud.store" : "Preview.store")
            let schema = Schema([SyncEvent.self])
            let config = ModelConfiguration("Dayline", schema: schema, url: storeURL, cloudKitDatabase: cloudEnabled ? .private(AppConfiguration.cloudContainer) : .none)
            container = try ModelContainer(for: schema, configurations: [config])
            container?.mainContext.autosaveEnabled = false
            try reload()
            ready = true
            syncStatus = cloudEnabled ? "等待 iCloud 状态" : "本机预览 · 尚未连接 iCloud"
            observeCloud()
            // Cloud imports and foregrounding drive refreshes; this is only a light recovery poll.
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in do { try self?.reload() } catch { self?.errorMessage = "读取任务失败：\(error.localizedDescription)" } }
            }
            #if os(macOS)
            if UserDefaults.standard.bool(forKey: "agentEnabled") { startAgent() }
            #endif
            Task { await refreshCloudStatus() }
        } catch {
            // A failed cloud store is never silently replaced by an empty local database.
            errorMessage = "无法打开任务库：\(error.localizedDescription)"; syncStatus = "任务库未打开"
        }
    }

    func reload() throws {
        guard let context = container?.mainContext else { return }
        var descriptor = FetchDescriptor<SyncEvent>()
        descriptor.propertiesToFetch = [\.logicalID, \.schema]
        let rows = try context.fetch(descriptor)
        var incoming: [ChangeEvent] = []
        var present: Set<String> = []
        for row in rows {
            guard row.schema == 1 else { throw CommandError("schema", "资料来自较新版本，请先升级 App。") }
            present.insert(row.logicalID)
            guard eventIndex.event(row.logicalID) == nil else { continue }
            let event = try JSONDecoder().decode(ChangeEvent.self, from: row.payload)
            guard event.schema == 1, event.id == row.logicalID else { throw CommandError("corrupt_event", "发现无法校验的操作记录，已停止更新显示。") }
            incoming.append(event)
        }
        if !projection.eventIDs.isSubset(of: present) {
            // Honour an authoritative store replacement without retaining ghost records.
            var replacement = EventIndex()
            try replacement.merge(present.compactMap { eventIndex.event($0) } + incoming)
            eventIndex = replacement
        } else if try !eventIndex.merge(incoming) { return }
        publishProjection()
        let migration = Structure.legacyChanges(projection)
        if !migration.isEmpty {
            let event = ChangeEvent(actor: actorID, clock: projection.clock + 1, changes: migration)
            do { context.insert(try SyncEvent(event: event)); try context.save() }
            catch { context.rollback(); throw error }
            try eventIndex.merge([event]); publishProjection()
        }
    }
    private func publishProjection() {
        events = eventIndex.events; projection = eventIndex.projection
    }

    @discardableResult func execute(_ request: AgentRequest) throws -> AgentResponse {
        guard request.version == 1 else { throw CommandError("unsupported_version", "不支持的协议版本。") }
        guard !request.requestID.isEmpty, request.requestID.utf8.count <= 200 else { throw CommandError("invalid_request", "requestID 不能为空或超过 200 字节。") }
        guard ready, let context = container?.mainContext else { throw CommandError("store_unavailable", "任务库不可用，未执行修改。") }
        try reload()
        if request.command == "status" {
            return AgentResponse(message: "\(syncStatus)；\(cloudDiagnostics)；任务 \(projection.tasks.count) 条；操作记录 \(projection.eventIDs.count) 条；本地 Agent \(agentStatus)。CLI 成功表示本机已保存，不代表其他设备已收到。")
        }
        if request.command == "history.list" {
            let offset = request.fields["offset"]?.number ?? 0, limit = request.fields["limit"]?.number ?? 50
            guard offset >= 0, (1...100).contains(limit) else { throw CommandError("invalid_page", "offset 应为非负整数，limit 范围为 1–100。") }
            let all = projection.visibleHistory(events).filter { request.id == nil || $0.changes.contains { $0.entity == request.id } }.sorted { $0.clock == $1.clock ? $0.id > $1.id : $0.clock > $1.clock }
            let page = all.dropFirst(offset).prefix(limit).map { event -> ChangeEvent in
                var preview = event
                preview.changes = event.changes.map { change in
                    var c = change
                    c.fields = c.fields.mapValues { value in
                        if case .string(let text) = value, text.utf8.count > 1000 { return .string(String(text.prefix(250)) + "…") }; return value
                    }
                    for key in ["richNotes", "snapshot"] where c.fields[key] != nil { c.fields[key] = .string("已保存；完整内容见 App 备份") }
                    return c
                }
                return preview
            }
            return AgentResponse(message: String(decoding: try JSONEncoder().encode(page), as: UTF8.self))
        }
        let prepared: PreparedCommand
        if request.command == "event.undo" {
            if projection.eventIDs.contains(request.requestID) { return AgentResponse(message: "撤回已执行。", eventID: request.requestID) }
            let event = try History.undo(request.id ?? "", events: events, requestID: request.requestID, actor: actorID)
            prepared = PreparedCommand(event: event, response: AgentResponse(message: "已撤回；原始历史仍保留。", eventID: event.id))
        } else { prepared = try Commands.prepare(request, projection: projection, actor: actorID) }
        if let event = prepared.event {
            do { context.insert(try SyncEvent(event: event)); try context.save() }
            catch { context.rollback(); throw error }
            // Save durably first, then publish this one event; no second fetch/decode/replay.
            try eventIndex.merge([event])
            publishProjection()
        }
        return prepared.response
    }

    @discardableResult func perform(_ command: String, id: String? = nil, fields: [String: Value] = [:], revision: String? = nil) -> AgentResponse? {
        do { return try execute(AgentRequest(command: command, id: id, expectedRevision: revision, fields: fields)) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func addQuick(_ input: String, listID: String = "inbox", parentID: String? = nil, due defaultDue: Date? = nil) -> String? {
        var fields: [String: Value] = ["title": .string(input), "listID": .string(listID), "allDay": .flag(true)]
        if let due = defaultDue { fields["due"] = .date(due) }
        if projection.records[listID]?["listType"].string == "note" { fields["itemType"] = .string("note"); fields["due"] = .null }
        if let parentID { fields["parentID"] = .string(parentID) }
        return perform("task.add", fields: fields)?.records.first?.id
    }

    func consumeSharedInbox() {
        #if os(iOS) && !DAYLINE_LOCAL
        do {
            for url in try FileManager.default.contentsOfDirectory(at: SharedInbox.directory(), includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let capture = try JSONDecoder().decode(SharedCapture.self, from: Data(contentsOf: url))
                _ = try execute(AgentRequest(command: "task.add", requestID: "share-" + capture.id, fields: ["title": .string(capture.title), "notes": .string(capture.notes)]))
                try FileManager.default.removeItem(at: url)
            }
        } catch { errorMessage = "接收分享内容失败：\(error.localizedDescription)" }
        #endif
    }
    func batch(_ ids: [String], action: String = "update", fields: [String: Value] = [:]) {
        var patch = fields; patch["ids"] = .strings(ids); patch["action"] = .string(action)
        perform("task.batch", fields: patch)
    }
    func update(_ id: String, _ fields: [String: Value]) { perform("task.update", id: id, fields: fields) }
    func toggle(_ task: Record) { perform(task.completed ? "task.reopen" : "task.complete", id: task.id) }
    func reschedule(_ task: Record, to date: Date) {
        var fields: [String: Value] = ["due": .date(date)]
        if let old = task.due {
            if let end = task.end { fields["end"] = .date(date.addingTimeInterval(end.timeIntervalSince(old))) }
        }
        update(task.id, fields)
    }

    func exportArchive() throws -> Data {
        try reload()
        let archive = EventArchive(format: "dayline-events", version: 1, exportedAt: Date(), events: events)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(archive)
    }
    func importArchive(_ data: Data) throws -> Int {
        guard data.count <= 50_000_000 else { throw CommandError("too_large", "导入文件超过 50 MB。") }
        let archive = try JSONDecoder().decode(EventArchive.self, from: data)
        guard archive.format == "dayline-events", archive.version == 1, archive.events.allSatisfy({ $0.schema == 1 && $0.clock > 0 && !$0.id.isEmpty }) else { throw CommandError("invalid_archive", "备份格式或版本无效。") }
        guard let context = container?.mainContext else { throw CommandError("store_unavailable", "任务库不可用。") }
        try reload()
        let known = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var unique: [String: ChangeEvent] = [:]
        for event in archive.events {
            if let existing = known[event.id] ?? unique[event.id], existing != event { throw CommandError("event_collision", "备份内出现同 ID、不同内容的操作，未导入。") }
            unique[event.id] = event
        }
        let incoming = unique.values.filter { known[$0.id] == nil }
        do { for event in incoming { context.insert(try SyncEvent(event: event)) }; try context.save() }
        catch { context.rollback(); throw error }
        try reload(); return incoming.count
    }

    func refreshCloudStatus() async {
        guard cloudEnabled else { return }
        do {
            let status = try await CKContainer(identifier: AppConfiguration.cloudContainer).accountStatus()
            cloudAvailable = status == .available
            switch status {
            case .available:
                if lastImport == nil && lastExport == nil { syncStatus = "iCloud 已登录 · 等待首次同步" }
                do {
                    let zones = try await CKContainer(identifier: AppConfiguration.cloudContainer).privateCloudDatabase.allRecordZones()
                    cloudDiagnostics = "私有数据库可访问，\(zones.count) 个数据区"
                } catch { cloudDiagnostics = Self.cloudErrorDescription(error) }
            case .noAccount: syncStatus = "尚未登录 iCloud · 修改暂存本机"
            case .restricted: syncStatus = "iCloud 访问受限 · 修改暂存本机"
            case .temporarilyUnavailable: syncStatus = "iCloud 暂不可用 · 修改暂存本机"
            default: syncStatus = "无法确认 iCloud 状态 · 修改暂存本机"
            }
        } catch { cloudAvailable = false; syncStatus = "iCloud 连接失败：\(error.localizedDescription)" }
    }
    private func observeCloud() {
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in
                guard let self else { return }
                if let error = event.error { self.syncStatus = "同步遇到问题：\(Self.cloudErrorDescription(error))"; return }
                if event.endDate == nil { self.syncStatus = "正在同步 iCloud…"; return }
                if event.succeeded {
                    if event.type == .import { self.lastImport = event.endDate }
                    if event.type == .export { self.lastExport = event.endDate }
                    self.syncStatus = "iCloud 最近一次同步成功"
                    if event.type == .import {
                        do { try self.reload() } catch { self.errorMessage = error.localizedDescription }
                    }
                }
            }
        })
    }

    private static func cloudErrorDescription(_ error: Error, depth: Int = 0) -> String {
        guard depth < 5 else { return error.localizedDescription }
        let ns = error as NSError
        var details: [String] = []
        if let status = ns.userInfo["CKHTTPStatus"] { details.append("HTTP \(status)") }
        for key in ["CKErrorDescription", NSDebugDescriptionErrorKey] {
            if let description = ns.userInfo[key] as? String { details.append(description) }
        }
        for key in [CKPartialErrorsByItemIDKey, "CKPartialErrors"] {
            if let partial = ns.userInfo[key] as? NSDictionary {
                details.append(contentsOf: partial.allValues.compactMap { $0 as? Error }.map { cloudErrorDescription($0, depth: depth + 1) })
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { details.append(cloudErrorDescription(underlying, depth: depth + 1)) }
        if !details.isEmpty { return Array(Set(details)).sorted().joined(separator: "；") }
        if let ck = error as? CKError {
            if let partial = ck.partialErrorsByItemID, !partial.isEmpty {
                return Array(Set(partial.values.map { cloudErrorDescription($0, depth: depth + 1) })).sorted().joined(separator: "；")
            }
            return "\(ck.localizedDescription) [CloudKit \(ck.errorCode)]"
        }
        return error.localizedDescription
    }

    #if os(macOS)
    func startAgent() {
        guard server == nil, ready else { return }
        do {
            let agent = AgentServer()
            try agent.start { [weak self] request in
                guard let self else { return AgentResponse(ok: false, message: "App 已关闭。", errorCode: "app_closed") }
                do { return try self.execute(request) }
                catch { return AgentResponse(ok: false, message: error.localizedDescription, errorCode: (error as? CommandError)?.code ?? "storage_error") }
            }
            server = agent; agentStatus = "已连接，仅当前 Mac 用户可访问"; UserDefaults.standard.set(true, forKey: "agentEnabled")
        } catch { errorMessage = error.localizedDescription; agentStatus = "连接失败" }
    }
    func stopAgent() { server?.stop(); server = nil; agentStatus = "未开启"; UserDefaults.standard.set(false, forKey: "agentEnabled") }
    #endif
}

struct EventArchive: Codable {
    var format: String
    var version: Int
    var exportedAt: Date
    var events: [ChangeEvent]
}
