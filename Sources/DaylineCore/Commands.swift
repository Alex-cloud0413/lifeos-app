import Foundation

public struct AgentRequest: Codable, Sendable {
    public var version = 1
    public var command: String
    public var id: String?
    public var requestID: String
    public var expectedRevision: String?
    public var fields: [String: Value]
    public var filter: TaskFilter?
    public init(command: String, id: String? = nil, requestID: String = UUID().uuidString, expectedRevision: String? = nil, fields: [String: Value] = [:], filter: TaskFilter? = nil) {
        self.command = command; self.id = id; self.requestID = requestID; self.expectedRevision = expectedRevision; self.fields = fields; self.filter = filter
    }
    private enum CodingKeys: String, CodingKey { case version, command, id, requestID, expectedRevision, fields, filter }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        command = try c.decode(String.self, forKey: .command)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        requestID = try c.decodeIfPresent(String.self, forKey: .requestID) ?? UUID().uuidString
        expectedRevision = try c.decodeIfPresent(String.self, forKey: .expectedRevision)
        fields = try c.decodeIfPresent([String: Value].self, forKey: .fields) ?? [:]
        filter = try c.decodeIfPresent(TaskFilter.self, forKey: .filter)
    }
}

public struct AgentResponse: Codable, Sendable {
    public var version = 1
    public var ok: Bool
    public var message: String
    public var records: [Record]
    public var eventID: String?
    public var errorCode: String?
    public init(ok: Bool = true, message: String = "", records: [Record] = [], eventID: String? = nil, errorCode: String? = nil) {
        self.ok = ok; self.message = message; self.records = records; self.eventID = eventID; self.errorCode = errorCode
    }
}

public struct CommandError: Error, LocalizedError, Sendable {
    public var code: String
    public var message: String
    public var errorDescription: String? { message }
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
}

public struct PreparedCommand: Sendable {
    public var event: ChangeEvent?
    public var response: AgentResponse
}

public enum Commands {
    public static func prepare(_ input: AgentRequest, projection p: Projection, actor: String, now: Date = Date(), calendar: Calendar = .current) throws -> PreparedCommand {
        var request = input
        if request.command.hasPrefix("project.") { request.command = request.command.replacingOccurrences(of: "project.", with: "list.") }
        guard request.version == 1 else { throw CommandError("unsupported_version", "不支持的协议版本。") }
        guard !request.requestID.isEmpty, request.requestID.utf8.count <= 200 else { throw CommandError("invalid_request", "requestID 不能为空或超过 200 字节。") }
        if p.eventIDs.contains(request.requestID) {
            let kind = ["direction.add":"direction", "list.add":"list", "filter.add":"filter", "template.save":"template"][request.command] ?? "task"
            let record = p.records[request.id ?? "\(kind):\(request.requestID)"]
            return PreparedCommand(response: AgentResponse(message: "此前操作已保存；没有重复执行。", records: record.map { [$0] } ?? [], eventID: request.requestID))
        }
        func result(_ records: [Record]) -> PreparedCommand { PreparedCommand(response: AgentResponse(records: records)) }
        func record(_ kind: String = "task") throws -> Record {
            guard let id = request.id, let r = p.records[id], r.kind == kind, !p.isPurged(r) else { throw CommandError("not_found", "找不到对应的\(kind == "task" ? "任务" : "记录")。") }
            if let expected = request.expectedRevision, expected != r.revision { throw CommandError("revision_conflict", "记录已更新，请重新读取后再修改。") }
            return r
        }
        if let structured = try Structure.prepare(request, projection: p, actor: actor, now: now) { return structured }
        if let advanced = try AdvancedCommands.prepare(request, projection: p, actor: actor, now: now, calendar: calendar) { return advanced }
        var changes: [Change] = []
        var resultIDs: [String] = []
        switch request.command {
        case "trash.list": return result(p.trashRecords)
        case "trash.empty":
            guard request.fields["confirm"]?.flag == true else { throw CommandError("confirmation_required", "清空后无法在 App 中恢复，请先确认。") }
            let records = p.trashRecords
            guard request.fields["ids"]?.strings == records.map(\.id), request.fields["revisions"]?.strings == records.map(\.revision) else {
                throw CommandError("revision_conflict", "回收站内容已改变，请重新查看并确认。")
            }
            changes = records.map { Change(entity: $0.id, kind: $0.kind, fields: ["purged": .flag(true)]) }
        case "task.list":
            let filter = request.filter ?? TaskFilter()
            guard ["all", "today", "tomorrow", "upcoming", "undated", "completed", "trash", "notes"].contains(filter.view) else { throw CommandError("invalid_view", "未知任务视图：\(filter.view)") }
            return result(p.query(filter, now: now, calendar: calendar))
        case "task.get": return result([try record()])
        case "list.list":
            if let direction = request.fields["directionID"] { return result(p.lists.filter { $0.directionID == direction.string }) }
            return result(p.lists)
        case "filter.list": return result(p.filters)
        case "task.add":
            let id = "task:\(request.requestID)"
            var fields: [String: Value] = ["title": .string(""), "priority": .number(0), "listID": .string("inbox"), "completed": .flag(false), "trashed": .flag(false), "allDay": .flag(true), "recurrence": .string("none"), "createdAt": .date(now)]
            fields.merge(request.fields) { _, new in new }
            if request.fields["listID"] == nil, let parent = fields["parentID"]?.string, let r = p.records[parent] { fields["listID"] = .string(r.listID) }
            try validateTask(request.fields, combined: fields, id: id, p: p)
            changes = [Change(entity: id, fields: fields)]; resultIDs = [id]
        case "task.update":
            let r = try record()
            guard !p.isHidden(r) else { throw CommandError("in_trash", "先从回收站恢复任务，再进行编辑。") }
            if let type = request.fields["itemType"]?.string, type != (r.isNote ? "note" : "task") { throw CommandError("use_conversion", "类型转换请使用 task.convert，以正确处理日期与完成状态。") }
            var patch = request.fields
            if patch["listID"] == nil, let parent = patch["parentID"]?.string, let parentTask = p.records[parent] { patch["listID"] = .string(parentTask.listID) }
            var combined = r.fields; combined.merge(patch) { _, new in new }
            try validateTask(patch, combined: combined, id: r.id, p: p)
            if patch.allSatisfy({ r[$0.key] == $0.value }) { return result([r]) }
            changes = [Change(entity: r.id, fields: patch)]; resultIDs = [r.id]
            if let project = patch["listID"]?.string, project != r.listID {
                changes += Structure.descendants(of: r.id, in: p).map { Change(entity: $0.id, fields: ["listID": .string(project)]) }
            }
        case "task.complete":
            let r = try record()
            guard !p.isHidden(r) else { throw CommandError("in_trash", "无法完成回收站中的任务。") }
            guard !r.isNote else { throw CommandError("is_note", "笔记没有完成状态，请先转换为任务。") }
            if r.completed { return result([r]) }
            var descendants: [Record] = []
            func collect(_ id: String) {
                for child in p.children(of: id) where !descendants.contains(where: { $0.id == child.id }) { descendants.append(child); collect(child.id) }
            }
            collect(r.id)
            changes = ([r] + descendants).filter { !$0.completed && !$0.isNote }.map { Change(entity: $0.id, fields: ["completed": .flag(true), "completedAt": .date(now)]) }
            resultIDs = [r.id]
            if let due = r.due, let next = Recurrence.next(after: due, rule: r.recurrence, calendar: calendar, anchor: r["repeatAnchor"].date ?? due) {
                let series = r["seriesID"].string ?? r.id
                let nextID = "\(series)@\(DateCodec.format(next))"
                if p.records[nextID] == nil {
                    var fields = r.fields
                    fields["due"] = .date(next); fields["completed"] = .flag(false); fields["completedAt"] = .null
                    fields["progress"] = .number(0); fields["createdAt"] = .date(now); fields["status"] = .string("todo")
                    fields["seriesID"] = .string(series); fields["repeatAnchor"] = .date(r["repeatAnchor"].date ?? due)
                    if let end = r.end { fields["end"] = .date(next.addingTimeInterval(end.timeIntervalSince(due))) }
                    fields.removeValue(forKey: "reminder")
                    changes.append(Change(entity: nextID, fields: fields))
                    for child in descendants {
                        var f = child.fields; f["completed"] = .flag(false); f["completedAt"] = .null; f["createdAt"] = .date(now)
                        f["progress"] = .number(0)
                        f["parentID"] = .string(child.parentID == r.id ? nextID : "\(nextID)/\(child.parentID!)")
                        if let childDue = child.due { f["due"] = .date(next.addingTimeInterval(childDue.timeIntervalSince(due))) }
                        if let childEnd = child.end { f["end"] = .date(next.addingTimeInterval(childEnd.timeIntervalSince(due))) }
                        f.removeValue(forKey: "reminder")
                        changes.append(Change(entity: "\(nextID)/\(child.id)", fields: f))
                    }
                } else if let existing = p.records[nextID], existing.trashed && !existing.completed {
                    changes.append(Change(entity: nextID, fields: ["trashed": .flag(false)]))
                }
                changes.append(Change(entity: r.id, fields: ["successorID": .string(nextID)])); resultIDs.append(nextID)
            }
        case "task.reopen":
            let r = try record()
            if let successor = r["successorID"].string, let next = p.records[successor], !next.trashed {
                throw CommandError("recurrence_successor_exists", "已生成下一次重复任务。先将下一次任务移入回收站，再恢复这一次，以免出现两个待办。")
            }
            changes = [Change(entity: r.id, fields: ["completed": .flag(false), "completedAt": .null])]; resultIDs = [r.id]
        case "task.trash", "task.restore":
            let r = try record()
            changes = [Change(entity: r.id, fields: ["trashed": .flag(request.command == "task.trash")])]; resultIDs = [r.id]
        case "list.add", "filter.add":
            let kind = request.command == "list.add" ? "list" : "filter"
            let id = "\(kind):\(request.requestID)"
            try validateGroup(request.fields, kind: kind, p: p)
            guard let title = request.fields["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError("invalid_title", "名称不能为空。") }
            changes = [Change(entity: id, kind: kind, fields: request.fields)]; resultIDs = [id]
        case "list.update", "filter.update":
            let kind = request.command == "list.update" ? "list" : "filter"
            let r = try record(kind); try validateGroup(request.fields, kind: kind, p: p)
            if kind == "list", request.fields["trashed"]?.flag == true, p.tasks.contains(where: { $0.listID == r.id && !p.isHidden($0) }) { throw CommandError("list_not_empty", "先移动或删除清单中的内容，再删除清单。") }
            changes = [Change(entity: r.id, kind: kind, fields: request.fields)]; resultIDs = [r.id]
        default: throw CommandError("unknown_command", "未知命令：\(request.command)")
        }
        // Record even an empty clear attempt so a retry cannot clear newly trashed content.
        if changes.isEmpty && request.command != "trash.empty" { return result([]) }
        let event = ChangeEvent(id: request.requestID, actor: actor, clock: p.clock + 1, createdAt: now, changes: changes)
        // Return the projected result without replacing existing records.
        var records = p.records
        for c in changes {
            var r = records[c.entity] ?? Record(id: c.entity, kind: c.kind, fields: [:], revision: "")
            r.fields.merge(c.fields) { _, new in new }; r.revision = event.id; records[c.entity] = r
        }
        return PreparedCommand(event: event, response: AgentResponse(message: "已保存到本机；iCloud 由系统异步同步。", records: resultIDs.compactMap { records[$0] }, eventID: event.id))
    }

    static func validateTask(_ patch: [String: Value], combined fields: [String: Value], id: String, p: Projection) throws {
        let strings: Set<String> = ["title", "notes", "richNotes", "itemType", "listID", "recurrence", "status", "section"]
        let nullableStrings: Set<String> = ["parentID"]
        let dates: Set<String> = ["due", "end"]
        for (key, value) in patch {
            if strings.contains(key) { guard let s = value.string, s.utf8.count <= (key == "richNotes" ? 500_000 : 100_000) else { throw CommandError("invalid_field", "\(key) 必须为文本，且不超过 100 KB。") } }
            else if nullableStrings.contains(key) { guard value == .null || value.string != nil else { throw CommandError("invalid_field", "\(key) 必须为文本或空值。") } }
            else if dates.contains(key) { guard value == .null || value.date != nil else { throw CommandError("invalid_date", "\(key) 必须是含时区的 ISO 8601 日期或空值。") } }
            else if key == "priority" { guard let v = value.number, (0...3).contains(v) else { throw CommandError("invalid_priority", "优先级范围为 0–3。") } }
            else if key == "progress" { guard let v = value.number, (0...100).contains(v) else { throw CommandError("invalid_progress", "进度范围为 0–100。") } }
            else if key == "rank" { guard value.number != nil else { throw CommandError("invalid_rank", "排序值必须为整数。") } }
            else if ["allDay", "pinned"].contains(key) { guard value.flag != nil else { throw CommandError("invalid_field", "allDay 必须为布尔值。") } }
            else if key == "tags" { guard let tags = value.strings, tags.count <= 50, tags.allSatisfy({ !$0.isEmpty && $0.count < 100 }) else { throw CommandError("invalid_tags", "标签必须为最多 50 个非空文本。") } }
            else { throw CommandError("unknown_field", "不允许修改字段：\(key)") }
        }
        guard let title = fields["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError("invalid_title", "任务标题不能为空。") }
        let list = fields["listID"]?.string ?? "inbox"
        guard list == "inbox" || p.lists.contains(where: { $0.id == list }) else { throw CommandError("invalid_list", "清单不存在。") }
        if let type = fields["itemType"]?.string, !["task", "note"].contains(type) { throw CommandError("invalid_type", "类型必须为 task 或 note。") }
        if fields["itemType"]?.string == "note" {
            guard ["due", "end"].allSatisfy({ fields[$0]?.date == nil }), (fields["recurrence"]?.string ?? "none") == "none" else { throw CommandError("note_schedule", "笔记不设置日程，请先转换为任务。") }
        }
        let recurrence = fields["recurrence"]?.string ?? "none"
        guard Recurrence.choices.contains(recurrence) else { throw CommandError("invalid_recurrence", "不支持的重复规则。") }
        guard recurrence == "none" || fields["due"]?.date != nil else { throw CommandError("missing_due", "重复任务需要设置日期。") }
        if let end = fields["end"]?.date {
            guard let due = fields["due"]?.date, end > due else { throw CommandError("invalid_duration", "结束时间必须晚于开始时间。") }
        }
        if let status = fields["status"]?.string, !["todo", "doing"].contains(status) { throw CommandError("invalid_status", "状态为 todo 或 doing；完成请使用 task.complete。") }
        if let parent = fields["parentID"]?.string {
            guard let r = p.records[parent], r.kind == "task", !p.isHidden(r) else { throw CommandError("invalid_parent", "父任务不存在或已移入回收站。") }
            guard r.listID == list else { throw CommandError("parent_project", "子任务必须与父任务属于同一专项；移动父任务会一起移动子任务。") }
            var current: String? = parent; var seen: Set<String> = [id]
            while let key = current {
                guard seen.insert(key).inserted else { throw CommandError("parent_cycle", "子任务不能形成循环。") }
                current = p.records[key]?.parentID
            }
        }
    }
    private static func validateGroup(_ fields: [String: Value], kind: String, p: Projection) throws {
        let keys: Set<String> = kind == "list" ? ["title", "color", "folder", "directionID", "archived", "trashed", "sections", "listType"] : ["title", "query", "trashed"]
        for (key, value) in fields {
            guard keys.contains(key) else { throw CommandError("unknown_field", "不允许修改字段：\(key)") }
            if key == "directionID" {
                guard value == .null || (p.records[value.string ?? ""]?.kind == "direction" && p.records[value.string ?? ""]?.trashed == false) else { throw CommandError("invalid_direction", "方向不存在。") }
                continue
            }
            if key == "sections" {
                guard let sections = value.strings, sections.count <= 30, Set(sections).count == sections.count, sections.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else { throw CommandError("invalid_sections", "分组名应唯一、非空，最多 30 组。") }
                continue
            }
            if key == "listType", !["task", "note"].contains(value.string ?? "") { throw CommandError("invalid_type", "清单类型无效。") }
            if key == "folder" && value == .null { continue }
            if ["archived", "trashed"].contains(key) { guard value.flag != nil else { throw CommandError("invalid_field", "\(key) 必须为布尔值。") } }
            else { guard let s = value.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.count < 10000 else { throw CommandError("invalid_field", "\(key) 必须为非空文本。") } }
            if key == "query" {
                guard let raw = value.string?.data(using: .utf8), (try? JSONDecoder().decode(TaskFilter.self, from: raw)) != nil else { throw CommandError("invalid_filter", "筛选条件格式无效。") }
            }
        }
    }
}
