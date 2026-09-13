import Foundation

public enum TaskReordering {
    public enum Placement: String { case before, after }

    public static func peers(_ a: Record, _ b: Record) -> Bool {
        a.kind == "task" && b.kind == "task" && a.listID == b.listID && a.parentID == b.parentID && a.pinned == b.pinned
    }

    /// Dropping below an expanded branch moves past that branch, without reparenting.
    public static func target(for source: Record, over row: Record, records: [String: Record]) -> Record? {
        if peers(source, row), source.id != row.id { return row }
        return TaskOutline.ancestors(of: row, records: records).last { peers(source, $0) && source.id != $0.id }
    }

    public static func insertion(for source: Record, at index: Int, rows: [Record], records: [String: Record]) -> (Record, Placement)? {
        guard (0...rows.count).contains(index), !rows.isEmpty else { return nil }
        if index < rows.count, peers(source, rows[index]), rows[index].id != source.id { return (rows[index], .before) }
        if index > 0, let target = target(for: source, over: rows[index - 1], records: records) { return (target, .after) }
        return nil
    }

    public static func changes(_ request: AgentRequest, projection p: Projection) throws -> [Change] {
        guard let sourceID = request.id, let source = p.records[sourceID], source.kind == "task", !p.isHidden(source),
              let targetID = request.fields["targetID"]?.string, let target = p.records[targetID], !p.isHidden(target),
              peers(source, target), sourceID != targetID,
              let placement = request.fields["placement"]?.string.flatMap(Placement.init(rawValue:)),
              let visibleIDs = request.fields["orderedIDs"]?.strings,
              (2...300).contains(visibleIDs.count), Set(visibleIDs).count == visibleIDs.count,
              visibleIDs.contains(sourceID), visibleIDs.contains(targetID) else {
            throw CommandError("invalid_move", "请拖到同一专项、同一父任务下的同级任务之间。置顶任务保持在顶部。")
        }
        let visible = try visibleIDs.map { id -> Record in
            guard let task = p.records[id], peers(source, task), !p.isHidden(task) else {
                throw CommandError("revision_conflict", "任务层级已变化，请重新拖动。")
            }
            return task
        }
        var order = visible.map(\.id).filter { $0 != sourceID }
        let insertion = order.firstIndex(of: targetID)! + (placement == .after ? 1 : 0)
        order.insert(sourceID, at: insertion)
        guard order != visibleIDs else { return [] }

        // Keep omitted/completed siblings in their old slots while reordering the visible subset.
        let siblings = TaskOrdering.sorted(p.tasks.filter { peers(source, $0) && !p.isHidden($0) }, by: "manual")
        let visibleSet = Set(visibleIDs)
        var remaining = order.makeIterator()
        let merged = siblings.map { visibleSet.contains($0.id) ? remaining.next()! : $0.id }
        var changes = merged.enumerated().compactMap { index, id -> Change? in
            let rank = index * 1024
            guard p.records[id]?.rank != rank else { return nil }
            return Change(entity: id, fields: ["rank": .number(rank)])
        }
        if let viewID = request.fields["viewID"]?.string {
            guard viewID.hasPrefix("view:"), viewID.count < 250 else { throw CommandError("invalid_view", "视图标识无效。") }
            if p.records[viewID]?["sort"].string != "manual" {
                changes.append(Change(entity: viewID, kind: "view", fields: ["sort": .string("manual")]))
            }
        }
        return changes
    }
}
