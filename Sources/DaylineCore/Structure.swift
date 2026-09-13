import Foundation

/// Directions own projects; projects retain their existing list IDs and task history.
public enum Structure {
    public static func projects(in direction: String?, projection: Projection) -> [Record] {
        projection.lists.filter { $0.directionID == direction && !$0.archived }
    }
    public static func descendants(of id: String, in projection: Projection) -> [Record] {
        var result: [Record] = []; var visited: Set<String> = [id]
        func collect(_ parent: String) {
            for task in projection.tasks where task.parentID == parent && visited.insert(task.id).inserted {
                result.append(task); collect(task.id)
            }
        }
        collect(id); return result
    }
    public static func legacyChanges(_ p: Projection) -> [Change] {
        var changes: [Change] = []; var created: Set<String> = []
        for project in p.lists where project.directionID == nil {
            guard let folder = project["folder"].string, !folder.isEmpty else { continue }
            let key = Data(folder.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let id = "direction:legacy:" + key
            if (p.records[id] == nil || p.records[id]?.trashed == true), created.insert(id).inserted {
                changes.append(Change(entity: id, kind: "direction", fields: ["title": .string(folder), "trashed": .flag(false)]))
            }
            changes.append(Change(entity: project.id, kind: "list", fields: ["directionID": .string(id), "folder": .null]))
        }
        return changes
    }
    public static func prepare(_ q: AgentRequest, projection p: Projection, actor: String, now: Date) throws -> PreparedCommand? {
        guard ["direction.list", "direction.add", "direction.update"].contains(q.command) else { return nil }
        if q.command == "direction.list" { return PreparedCommand(response: AgentResponse(records: p.directions)) }
        for (key, value) in q.fields {
            if key == "trashed" { guard value.flag != nil else { throw CommandError("invalid_field", "trashed 必须为布尔值。") } }
            else if key == "title" || key == "notes" {
                guard let text = value.string, text.utf8.count <= 10_000, key != "title" || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError("invalid_field", "方向名称不能为空，文字不能超过 10 KB。") }
            } else { throw CommandError("unknown_field", "不允许修改字段：\(key)") }
        }
        let id: String
        if q.command == "direction.add" {
            guard let title = q.fields["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError("invalid_title", "请输入方向名称。") }
            id = "direction:" + q.requestID
        } else {
            guard let existing = q.id.flatMap({ p.records[$0] }), existing.kind == "direction", !p.isPurged(existing) else { throw CommandError("not_found", "找不到这个方向。") }
            id = existing.id
            if let revision = q.expectedRevision, revision != existing.revision { throw CommandError("revision_conflict", "方向已更新，请重新读取。") }
            if q.fields["trashed"]?.flag == true, p.lists.contains(where: { $0.directionID == id }) { throw CommandError("direction_not_empty", "先移动或删除方向内的专项。") }
            if q.fields.allSatisfy({ existing[$0.key] == $0.value }) { return PreparedCommand(response: AgentResponse(records: [existing])) }
        }
        let event = ChangeEvent(id: q.requestID, actor: actor, clock: p.clock + 1, createdAt: now, changes: [Change(entity: id, kind: "direction", fields: q.fields)])
        var next = p; next.apply(event)
        return PreparedCommand(event: event, response: AgentResponse(records: next.records[id].map { [$0] } ?? [], eventID: event.id))
    }
}

/// A filtered tree keeps the ancestor path, sorts siblings together, and never duplicates a task.
public struct TaskOutline {
    public struct Row: Identifiable {
        public var id: String { task.id }
        public let task: Record
        public let depth: Int
        public let rootID: String
        public let hasChildren: Bool
        public let isMatch: Bool
    }
    public let roots: [Record]
    private let children: [String: [Record]]
    private let matches: Set<String>

    public init(matching tasks: [Record], records: [String: Record], sort: String) {
        matches = Set(tasks.map(\.id))
        var included = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in tasks {
            for ancestor in Self.ancestors(of: task, records: records) { included[ancestor.id] = ancestor }
        }
        var branches: [String: [Record]] = [:]
        var top: [Record] = []
        for task in included.values {
            if let parent = task.parentID, included[parent] != nil { branches[parent, default: []].append(task) }
            else { top.append(task) }
        }
        children = branches.mapValues { TaskOrdering.sorted($0, by: sort) }
        roots = TaskOrdering.sorted(top, by: sort)
    }
    public static func ancestors(of task: Record, records: [String: Record]) -> [Record] {
        var result: [Record] = []; var seen: Set<String> = [task.id]; var parentID = task.parentID
        while let id = parentID, seen.insert(id).inserted,
              let parent = records[id], parent.kind == "task", parent.listID == task.listID {
            result.append(parent); parentID = parent.parentID
        }
        return result.reversed()
    }
    public func rows(collapsed: Set<String> = []) -> [Row] {
        var result: [Row] = []; var visited: Set<String> = []
        var stack = roots.reversed().map { ($0, 0, $0.id) }
        while let (task, depth, rootID) = stack.popLast() {
            guard visited.insert(task.id).inserted else { continue }
            let descendants = children[task.id] ?? []
            result.append(Row(task: task, depth: depth, rootID: rootID, hasChildren: !descendants.isEmpty, isMatch: matches.contains(task.id)))
            if !collapsed.contains(task.id) {
                stack.append(contentsOf: descendants.reversed().map { ($0, depth + 1, rootID) })
            }
        }
        return result
    }
}
