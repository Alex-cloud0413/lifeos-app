import Foundation

public enum AdvancedCommands {
    public static func prepare(_ q: AgentRequest, projection p: Projection, actor: String, now: Date, calendar: Calendar) throws -> PreparedCommand? {
        let supported = ["task.batch", "task.reorder", "task.move", "task.duplicate", "task.convert", "template.save", "template.use", "template.list", "template.trash", "view.update"]
        guard supported.contains(q.command) else { return nil }
        func require(_ id: String?, kind: String = "task") throws -> Record {
            guard let id, let r = p.records[id], r.kind == kind, !r.trashed, !p.isPurged(r) else { throw CommandError("not_found", "找不到可用的记录。") }
            if let revision = q.expectedRevision, revision != r.revision { throw CommandError("revision_conflict", "记录已变化，请重新读取。") }
            return r
        }
        func finish(_ changes: [Change], _ ids: [String]) -> PreparedCommand {
            if changes.isEmpty { return PreparedCommand(response: AgentResponse(records: ids.compactMap { p.records[$0] })) }
            let event = ChangeEvent(id: q.requestID, actor: actor, clock: p.clock + 1, createdAt: now, changes: changes)
            var next = p; next.apply(event)
            return PreparedCommand(event: event, response: AgentResponse(records: ids.compactMap { next.records[$0] }, eventID: event.id))
        }
        switch q.command {
        case "task.move":
            return finish(try TaskReordering.changes(q, projection: p), q.id.map { [$0] } ?? [])
        case "task.batch", "task.reorder":
            guard let ids = q.fields["ids"]?.strings, !ids.isEmpty, ids.count <= 300, Set(ids).count == ids.count else { throw CommandError("invalid_batch", "请指定 1–300 个不同的任务 ID。") }
            let action = q.command == "task.reorder" ? "update" : (q.fields["action"]?.string ?? "update")
            guard ["update", "postpone", "complete", "reopen", "trash", "restore"].contains(action) else { throw CommandError("invalid_batch", "不支持这类批量操作。") }
            var working = p; var changes: [Change] = []
            var fields = q.fields; fields.removeValue(forKey: "ids"); fields.removeValue(forKey: "action")
            let days = fields.removeValue(forKey: "days")?.number ?? 1
            if action == "postpone", !(1...366).contains(days) { throw CommandError("invalid_postpone", "延期天数范围为 1–366。") }
            for (index, id) in ids.enumerated() {
                if q.command == "task.reorder" { fields = ["rank": .number(index * 1024)] }
                var itemFields = fields
                if action == "postpone" {
                    guard let old = working.records[id]?.due, let date = calendar.date(byAdding: .day, value: days, to: old) else { throw CommandError("missing_due", "所选任务须已有日期才能按天延期。") }
                    itemFields["due"] = .date(date)
                }
                if let date = itemFields["due"]?.date, let r = working.records[id], let old = r.due {
                    if fields["end"] == nil, let end = r.end { itemFields["end"] = .date(date.addingTimeInterval(end.timeIntervalSince(old))) }
                }
                let part = AgentRequest(command: "task.\(action == "postpone" ? "update" : action)", id: id, requestID: "\(q.requestID)/\(index)", fields: itemFields)
                let prepared = try Commands.prepare(part, projection: working, actor: actor, now: now, calendar: calendar)
                if let event = prepared.event { working.apply(event); changes += event.changes }
            }
            return finish(changes, ids)
        case "task.convert":
            let r = try require(q.id)
            guard let type = q.fields["itemType"]?.string, ["task", "note"].contains(type) else { throw CommandError("invalid_type", "请选择任务或笔记。") }
            guard r.recurrence == "none", r["successorID"].string == nil else { throw CommandError("recurring_conversion", "请先复制为普通任务，再转换重复任务。") }
            var fields: [String: Value] = ["itemType": .string(type)]
            if type == "note" { fields.merge(["due": .null, "end": .null, "reminder": .null, "completed": .flag(false), "completedAt": .null, "progress": .number(0)]) { _, n in n } }
            return finish([Change(entity: r.id, fields: fields)], [r.id])
        case "template.list": return PreparedCommand(response: AgentResponse(records: p.templates))
        case "template.trash":
            let r = try require(q.id, kind: "template")
            return finish([Change(entity: r.id, kind: "template", fields: ["trashed": .flag(true)])], [r.id])
        case "view.update":
            guard let id = q.id, id.hasPrefix("view:"), id.count < 250 else { throw CommandError("invalid_view", "视图标识无效。") }
            for (key, value) in q.fields {
                if key == "sort" { guard ["manual", "priority", "date", "title", "created"].contains(value.string ?? "") else { throw CommandError("invalid_sort", "排序方式无效。") } }
                else if key == "group" { guard ["none", "section", "list", "priority"].contains(value.string ?? "") else { throw CommandError("invalid_group", "分组方式无效。") } }
                else { throw CommandError("unknown_field", "不支持此视图设置。") }
            }
            return finish([Change(entity: id, kind: "view", fields: q.fields)], [id])
        case "template.save", "task.duplicate", "template.use":
            var items: [Record]
            if q.command == "template.use" {
                let template = try require(q.id, kind: "template")
                guard let data = template["snapshot"].string?.data(using: .utf8) else { throw CommandError("invalid_template", "模板内容不可用。") }
                items = try JSONDecoder().decode([Record].self, from: data)
            } else {
                let root = try require(q.id); items = [root]
                func collect(_ id: String) { for child in p.children(of: id) { items.append(child); collect(child.id) } }
                collect(root.id)
            }
            guard let root = items.first, items.count <= 300 else { throw CommandError("invalid_template", "模板为空或超过 300 项。") }
            if q.command == "template.save" {
                let id = "template:\(q.requestID)"
                let data = try JSONEncoder().encode(items)
                guard data.count < 800_000 else { throw CommandError("too_large", "模板内容超过 800 KB。") }
                let fields: [String: Value] = ["title": .string(q.fields["title"]?.string ?? root.title), "snapshot": .string(String(decoding: data, as: UTF8.self)), "createdAt": .date(now)]
                return finish([Change(entity: id, kind: "template", fields: fields)], [id])
            }
            let rootID = "task:\(q.requestID)"
            let mapping = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset == 0 ? rootID : "\(rootID)/\($0.offset)") })
            let anchor = q.fields["anchor"]?.date
            let originalBase = calendar.startOfDay(for: root.due ?? root.createdAt)
            var changes: [Change] = []; var working = p
            for (index, item) in items.enumerated() {
                var fields = item.fields
                fields.removeValue(forKey: "reminder")
                for key in ["seriesID", "successorID", "repeatAnchor", "completedAt", "completed", "trashed", "createdAt"] { fields.removeValue(forKey: key) }
                fields["completed"] = .flag(false); fields["trashed"] = .flag(false); fields["createdAt"] = .date(now)
                fields["progress"] = .number(0); fields["pinned"] = .flag(false); fields["status"] = .string("todo")
                fields["parentID"] = item.parentID.flatMap { mapping[$0] }.map(Value.string) ?? .null
                if let list = q.fields["listID"]?.string { fields["listID"] = .string(list) }
                else if item.listID != "inbox", p.records[item.listID]?.trashed != false { fields["listID"] = .string("inbox") }
                if index == 0, let title = q.fields["title"]?.string { fields["title"] = .string(title) }
                else if index == 0 && q.command == "task.duplicate" { fields["title"] = .string(root.title + "（副本）") }
                if q.command == "template.use" {
                    for key in ["due", "end"] {
                        if let anchor, let old = item[key].date {
                            let days = calendar.dateComponents([.day], from: originalBase, to: calendar.startOfDay(for: old)).day ?? 0
                            let base = calendar.date(byAdding: .day, value: days, to: anchor)!
                            let time = calendar.dateComponents([.hour, .minute, .second], from: old)
                            fields[key] = .date(calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: base))
                        } else { fields[key] = .null }
                    }
                    if fields["due"]?.date == nil { fields["recurrence"] = .string("none") }
                }
                var editable = fields
                for key in ["completed", "trashed", "createdAt"] { editable.removeValue(forKey: key) }
                try Commands.validateTask(editable, combined: fields, id: mapping[item.id]!, p: working)
                let change = Change(entity: mapping[item.id]!, fields: fields); changes.append(change)
                working.apply(ChangeEvent(id: "\(q.requestID)/copy/\(index)", actor: actor, clock: working.clock + 1, changes: [change]))
            }
            return finish(changes, [rootID])
        default: return nil
        }
    }
}

public enum TaskOrdering {
    public static func sorted(_ tasks: [Record], by mode: String) -> [Record] {
        tasks.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            switch mode {
            case "manual": if a.rank != b.rank { return a.rank < b.rank }
            case "title": if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            case "created": if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            case "date": if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            default:
                if a.priority != b.priority { return a.priority > b.priority }
                if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            }
            return a.id < b.id
        }
    }
}

public enum History {
    public static func undo(_ id: String, events: [ChangeEvent], requestID: String, actor: String, now: Date = Date()) throws -> ChangeEvent {
        guard let target = events.first(where: { $0.id == id }) else { throw CommandError("not_found", "找不到这次修改。") }
        let current = Projection(events: events)
        guard !target.changes.contains(where: { $0.fields["purged"]?.flag == true || current.records[$0.entity].map(current.isPurged) == true }) else {
            throw CommandError("permanently_removed", "清空回收站的内容无法撤回或恢复。")
        }
        let earlier = events.filter { event in
            if event.clock != target.clock { return event.clock < target.clock }
            if event.actor != target.actor { return event.actor < target.actor }
            return event.id < target.id
        }
        let before = Projection(events: earlier)
        var inverse: [Change] = []
        let created = Set(target.changes.filter { before.records[$0.entity] == nil }.map(\.entity))
        for change in target.changes {
            for key in change.fields.keys {
                guard current.fieldRevisions[change.entity]?[key] == id else { throw CommandError("undo_conflict", "这项内容之后又被修改，不能直接撤回；请查看历史后手动处理。") }
            }
            if created.contains(change.entity) {
                guard current.records[change.entity]?.revision == id else { throw CommandError("undo_conflict", "创建后已有新的修改，不能撤回创建。") }
                if current.records.values.contains(where: { !created.contains($0.id) && !$0.trashed && ($0.parentID == change.entity || $0.listID == change.entity) }) {
                    throw CommandError("undo_dependency", "已有后续任务使用这条记录，不能撤回创建操作。")
                }
                if !inverse.contains(where: { $0.entity == change.entity }) { inverse.append(Change(entity: change.entity, kind: change.kind, fields: ["trashed": .flag(true)])) }
            } else {
                let fields = Dictionary(uniqueKeysWithValues: change.fields.keys.map { ($0, before.records[change.entity]?[$0] ?? .null) })
                inverse.append(Change(entity: change.entity, kind: change.kind, fields: fields))
            }
        }
        return ChangeEvent(id: requestID, actor: actor, clock: current.clock + 1, createdAt: now, changes: inverse)
    }
}
