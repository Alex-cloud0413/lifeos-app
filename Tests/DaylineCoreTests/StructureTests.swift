import XCTest
@testable import DaylineCore

final class StructureTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_789_286_400)
    @discardableResult private func apply(_ command: String, _ id: String? = nil, _ fields: [String: Value] = [:], events: inout [ChangeEvent], requestID: String = UUID().uuidString) throws -> AgentResponse {
        let result = try Commands.prepare(AgentRequest(command: command, id: id, requestID: requestID, fields: fields), projection: Projection(events: events), actor: "test", now: now)
        if let event = result.event { events.append(event) }; return result.response
    }
    func testDirectionProjectTaskHierarchyDoesNotRequireDates() throws {
        var events: [ChangeEvent] = []
        let direction = try apply("direction.add", nil, ["title": .string("学习")], events: &events, requestID: "d").records[0]
        let retry = try apply("direction.add", nil, ["title": .string("学习")], events: &events, requestID: "d")
        XCTAssertEqual(retry.records.first?.id, direction.id); XCTAssertEqual(events.count, 1)
        let project = try apply("project.add", nil, ["title": .string("阅读"), "directionID": .string(direction.id)], events: &events).records[0]
        let root = try apply("task.add", nil, ["title": .string("一本书"), "listID": .string(project.id)], events: &events).records[0]
        let child = try apply("task.add", nil, ["title": .string("第一章"), "parentID": .string(root.id)], events: &events).records[0]
        XCTAssertEqual(child.listID, project.id); XCTAssertNil(child.due); XCTAssertNil(root.due)
        var filter = TaskFilter(); filter.directionID = direction.id
        let p = Projection(events: events)
        XCTAssertEqual(p.query(filter).count, 2)
        XCTAssertEqual(try apply("project.list", nil, ["directionID": .string(direction.id)], events: &events).records.map(\.id), [project.id])
        XCTAssertTrue(try apply("project.list", nil, ["directionID": .string("other")], events: &events).records.isEmpty)
        XCTAssertEqual(Structure.projects(in: direction.id, projection: p).map(\.id), [project.id])
        filter.directionID = "direction:other"; XCTAssertTrue(p.query(filter).isEmpty)
    }
    func testMoveRootMovesWholeSubtreeAndUndoRestoresIt() throws {
        var events: [ChangeEvent] = []
        let a = try apply("project.add", nil, ["title": .string("A")], events: &events).records[0]
        let b = try apply("project.add", nil, ["title": .string("B")], events: &events).records[0]
        let root = try apply("task.add", nil, ["title": .string("Root"), "listID": .string(a.id)], events: &events).records[0]
        let child = try apply("task.add", nil, ["title": .string("Child"), "parentID": .string(root.id)], events: &events).records[0]
        let leaf = try apply("task.add", nil, ["title": .string("Leaf"), "parentID": .string(child.id)], events: &events).records[0]
        let move = try apply("task.update", root.id, ["listID": .string(b.id)], events: &events)
        let p = Projection(events: events)
        for id in [root.id, child.id, leaf.id] { XCTAssertEqual(p.records[id]?.listID, b.id) }
        XCTAssertThrowsError(try apply("task.update", child.id, ["listID": .string(a.id)], events: &events))
        let undo = try History.undo(move.eventID!, events: events, requestID: "undo", actor: "test")
        let restored = Projection(events: events + [undo])
        for id in [root.id, child.id, leaf.id] { XCTAssertEqual(restored.records[id]?.listID, a.id) }
    }
    func testDirectionAndProjectScopesStillApplyToCompletedAndTrash() throws {
        var events: [ChangeEvent] = []
        let direction = try apply("direction.add", nil, ["title": .string("D")], events: &events).records[0]
        let project = try apply("project.add", nil, ["title": .string("P"), "directionID": .string(direction.id)], events: &events).records[0]
        let owned = try apply("task.add", nil, ["title": .string("Owned"), "listID": .string(project.id)], events: &events).records[0]
        let other = try apply("task.add", nil, ["title": .string("Other")], events: &events).records[0]
        for id in [owned.id, other.id] { try apply("task.complete", id, events: &events) }
        for view in ["completed", "trash"] {
            if view == "trash" { for id in [owned.id, other.id] { try apply("task.trash", id, events: &events) } }
            let p = Projection(events: events)
            var scoped = TaskFilter(view: view); scoped.directionID = direction.id
            XCTAssertEqual(p.query(scoped).map(\.id), [owned.id])
            XCTAssertEqual(p.query(TaskFilter(view: view, listID: project.id)).map(\.id), [owned.id])
        }
    }
    func testInvalidDirectionAndDeletingNonemptyDirectionAreRejected() throws {
        var events: [ChangeEvent] = []
        XCTAssertThrowsError(try apply("project.add", nil, ["title": .string("X"), "directionID": .string("missing")], events: &events))
        let direction = try apply("direction.add", nil, ["title": .string("D")], events: &events).records[0]
        let project = try apply("project.add", nil, ["title": .string("P"), "directionID": .string(direction.id)], events: &events).records[0]
        let snapshot = events
        XCTAssertThrowsError(try apply("direction.update", direction.id, ["trashed": .flag(true)], events: &events))
        XCTAssertEqual(events, snapshot)
        try apply("project.update", project.id, ["directionID": .null], events: &events)
        try apply("direction.update", direction.id, ["trashed": .flag(true)], events: &events)
        XCTAssertTrue(Projection(events: events).directions.isEmpty)
    }
    func testLegacyFoldersMigrateIdempotentlyAndConvergeAcrossDevices() throws {
        var events: [ChangeEvent] = []
        let a = try apply("list.add", nil, ["title": .string("A"), "folder": .string("学习 / 研究")], events: &events).records[0]
        let b = try apply("list.add", nil, ["title": .string("B"), "folder": .string("学习 / 研究")], events: &events).records[0]
        let task = try apply("task.add", nil, ["title": .string("原任务"), "listID": .string(a.id)], events: &events).records[0]
        let before = Projection(events: events); let changes = Structure.legacyChanges(before)
        let x = ChangeEvent(actor: "Mac", clock: before.clock + 1, changes: changes)
        let y = ChangeEvent(actor: "Phone", clock: before.clock + 1, changes: changes)
        let after = Projection(events: events + [y, x])
        XCTAssertEqual(after.directions.count, 1)
        XCTAssertEqual(after.records[a.id]?.directionID, after.records[b.id]?.directionID)
        XCTAssertEqual(after.records[task.id], task)
        XCTAssertTrue(Structure.legacyChanges(after).isEmpty)
        XCTAssertEqual(after.records, Projection(events: events + [x, y]).records)
    }
    func testRemovedReminderWritesAreRejectedAndLegacyCopiesDoNotReviveThem() throws {
        var events: [ChangeEvent] = []
        XCTAssertThrowsError(try apply("task.add", nil, ["title": .string("X"), "reminder": .date(now)], events: &events))
        let legacy = ChangeEvent(actor: "old", clock: 1, changes: [Change(entity: "task:legacy", fields: ["title": .string("旧任务"), "due": .date(now), "reminder": .date(now), "recurrence": .string("weekly")])])
        events = [legacy]
        try apply("task.update", "task:legacy", ["title": .string("仍可编辑")], events: &events)
        XCTAssertThrowsError(try apply("task.batch", nil, ["ids": .strings(["task:legacy"]), "reminder": .date(now)], events: &events))
        let copied = try apply("task.duplicate", "task:legacy", events: &events).records[0]
        XCTAssertNil(copied.fields["reminder"])
        let next = try apply("task.complete", "task:legacy", events: &events).records[1]
        XCTAssertNil(next.fields["reminder"])
    }
    func testDirectionFilterSurvivesCodingAndOldFiltersRemainReadable() throws {
        var filter = TaskFilter(); filter.directionID = "direction:1"
        let copy = try JSONDecoder().decode(TaskFilter.self, from: JSONEncoder().encode(filter))
        XCTAssertEqual(copy.directionID, filter.directionID)
        XCTAssertNil(try JSONDecoder().decode(TaskFilter.self, from: Data("{}".utf8)).directionID)
    }
}

final class TaskOutlineTests: XCTestCase {
    private func task(_ id: String, _ parent: String? = nil, priority: Int = 0) -> Record {
        var fields: [String: Value] = ["title": .string(id), "listID": .string("inbox"), "priority": .number(priority)]
        if let parent { fields["parentID"] = .string(parent) }
        return Record(id: id, kind: "task", fields: fields, revision: "test")
    }
    func testSiblingsSortWithoutSeparatingChildrenFromTheirParents() {
        let records = [task("A"), task("B"), task("A.1", "A"), task("A.2", "A", priority: 3), task("A.2.1", "A.2")]
        let outline = TaskOutline(matching: records, records: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }), sort: "priority")
        XCTAssertEqual(outline.rows().map(\.id), ["A", "A.2", "A.2.1", "A.1", "B"])
        XCTAssertEqual(outline.rows().map(\.depth), [0, 1, 2, 1, 0])
        XCTAssertEqual(outline.rows(collapsed: ["A.2"]).map(\.id), ["A", "A.2", "A.1", "B"])
        XCTAssertEqual(outline.rows(collapsed: ["A"]).map(\.id), ["A", "B"])
    }
    func testSearchShowsAncestorContextButNoUnmatchedSibling() {
        let records = [task("Root"), task("Child", "Root"), task("Leaf", "Child"), task("Sibling", "Root")]
        let outline = TaskOutline(matching: [records[2]], records: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }), sort: "title")
        XCTAssertEqual(outline.rows().map(\.id), ["Root", "Child", "Leaf"])
        XCTAssertEqual(outline.rows().map(\.isMatch), [false, false, true])
    }
    func testCompletedParentKeepsReopenedDescendantVisibleAndNoDuplicates() {
        let records = [task("Root"), task("Child", "Root"), task("Leaf", "Child")]
        let dictionary = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let outline = TaskOutline(matching: [records[2], records[1]], records: dictionary, sort: "title")
        XCTAssertEqual(outline.rows().map(\.id), ["Root", "Child", "Leaf"])
        XCTAssertEqual(TaskOutline.ancestors(of: records[2], records: dictionary).map(\.id), ["Root", "Child"])
    }
    func testThirtyTwoLevelsCreateEditMoveCompleteAndRestoreWithoutFlattening() throws {
        var events: [ChangeEvent] = []
        func apply(_ request: AgentRequest) throws -> AgentResponse {
            let prepared = try Commands.prepare(request, projection: Projection(events: events), actor: "test")
            if let event = prepared.event { events.append(event) }; return prepared.response
        }
        var ids: [String] = []
        for level in 0..<32 {
            var fields: [String: Value] = ["title": .string("Level \(level)")]
            if let parent = ids.last { fields["parentID"] = .string(parent) }
            ids.append(try apply(AgentRequest(command: "task.add", fields: fields)).records[0].id)
        }
        _ = try apply(AgentRequest(command: "task.update", id: ids.last, fields: ["notes": .string("Deep edit")]))
        XCTAssertThrowsError(try apply(AgentRequest(command: "task.update", id: ids[0], fields: ["parentID": .string(ids.last!)])))
        let project = try apply(AgentRequest(command: "project.add", fields: ["title": .string("Moved")])).records[0].id
        _ = try apply(AgentRequest(command: "task.update", id: ids[0], fields: ["listID": .string(project)]))
        var projection = Projection(events: events)
        XCTAssertTrue(ids.allSatisfy { projection.records[$0]?.listID == project })
        XCTAssertEqual(TaskOutline(matching: projection.query(TaskFilter()), records: projection.records, sort: "title").rows().map(\.depth), Array(0..<32))
        _ = try apply(AgentRequest(command: "task.complete", id: ids[0]))
        _ = try apply(AgentRequest(command: "task.trash", id: ids[0]))
        XCTAssertEqual(Projection(events: events).query(TaskFilter(view: "trash")).count, 32)
        _ = try apply(AgentRequest(command: "task.restore", id: ids[0]))
        projection = Projection(events: events)
        XCTAssertEqual(projection.query(TaskFilter(view: "completed")).count, 32)
        XCTAssertEqual(projection.records[ids.last!]?.notes, "Deep edit")
        XCTAssertEqual(TaskOutline.ancestors(of: projection.records[ids.last!]!, records: projection.records).map(\.id), Array(ids.dropLast()))
    }
}
