import XCTest
@testable import DaylineCore

final class NavigationAndReorderTests: XCTestCase {
    func fixture() -> [ChangeEvent] {
        [ChangeEvent(id: "seed", actor: "test", clock: 1, changes: [
            Change(entity: "direction:career", kind: "direction", fields: ["title": .string("事业")]),
            Change(entity: "list:content", kind: "list", fields: ["title": .string("内容"), "directionID": .string("direction:career")]),
            Change(entity: "list:other", kind: "list", fields: ["title": .string("其他")]),
            task("a", rank: 0), task("b", rank: 1024), task("c", rank: 2048),
            task("a1", parent: "a", rank: 0), task("a2", parent: "a", rank: 1024),
            task("a11", parent: "a1"), task("a111", parent: "a11"), task("b1", parent: "b"),
            Change(entity: "task:other", fields: ["title": .string("其他专项"), "listID": .string("list:other")])
        ])]
    }
    func task(_ name: String, parent: String? = nil, rank: Int = 0) -> Change {
        Change(entity: "task:" + name, fields: ["title": .string(name), "listID": .string("list:content"), "parentID": parent.map { .string("task:" + $0) } ?? .null, "rank": .number(rank), "notes": .string("正文 " + name)])
    }
    func move(_ source: String, _ target: String, _ placement: String, ids: [String], requestID: String = "move") -> AgentRequest {
        AgentRequest(command: "task.move", id: "task:" + source, requestID: requestID, fields: ["targetID": .string("task:" + target), "placement": .string(placement), "orderedIDs": .strings(ids.map { "task:" + $0 }), "viewID": .string("view:list:content")])
    }
    func testTaskPushAndBackEachPopExactlyOneLevel() {
        let p = Projection(events: fixture())
        var path = TaskNavigation.pages(for: "list:content", records: p.records)
        XCTAssertEqual(path, [.page("direction:career"), .page("list:content")])
        path = TaskNavigation.opening("task:a", from: path, projection: p)
        path = TaskNavigation.opening("task:a1", from: path, projection: p)
        XCTAssertEqual(path, [.page("direction:career"), .page("list:content"), .task("task:a"), .task("task:a1")])
        path.removeLast(); XCTAssertEqual(path.last, .task("task:a"))
        path.removeLast(); XCTAssertEqual(path.last, .page("list:content"))
        path.removeLast(); XCTAssertEqual(path.last, .page("direction:career"))
        path.removeLast(); XCTAssertTrue(path.isEmpty)
    }
    func testAncestorLinkPopsAndDeepLinkBuildsNoRedundantHomePage() {
        let p = Projection(events: fixture())
        let path = TaskNavigation.opening("task:a", from: [], projection: p)
        XCTAssertEqual(path, [.page("direction:career"), .page("list:content"), .task("task:a")])
        let child = TaskNavigation.opening("task:a1", from: path, projection: p)
        XCTAssertEqual(TaskNavigation.opening("task:a", from: child, projection: p), path)
        XCTAssertEqual(TaskNavigation.pages(for: "structure", records: p.records), [])
        XCTAssertEqual(TaskNavigation.pages(for: "list:other", records: p.records), [.page("list:other")])
        XCTAssertEqual(TaskNavigation.opening("task:a", from: [.page("list:other")], projection: p), path)
    }
    func testParentMovePreservesWholeSubtreeAndCanUndoAndReplayOnAnotherDevice() throws {
        let events = fixture(), before = Projection(events: events)
        let request = move("a", "c", "after", ids: ["a", "b", "c"])
        let event = try XCTUnwrap(Commands.prepare(request, projection: before, actor: "mac").event)
        let after = Projection(events: events + [event])
        let rows = TaskOutline(matching: after.query(TaskFilter()), records: after.records, sort: "manual").rows()
        XCTAssertEqual(rows.filter { $0.task.listID == "list:content" }.map(\.id), ["task:b", "task:b1", "task:c", "task:a", "task:a1", "task:a11", "task:a111", "task:a2"])
        for id in ["a1", "a2", "a11", "a111", "b1"] { XCTAssertEqual(after.records["task:" + id], before.records["task:" + id]) }
        XCTAssertEqual(after.records["view:list:content"]?["sort"].string, "manual")
        XCTAssertEqual(Projection(events: [event] + events).records, after.records)
        XCTAssertNil(try Commands.prepare(request, projection: after, actor: "phone").event)
        let undo = try History.undo(event.id, events: events + [event], requestID: "undo", actor: "mac")
        let restored = Projection(events: events + [event, undo])
        for id in ["a", "b", "c"] { XCTAssertEqual(restored.records["task:" + id]?.rank, before.records["task:" + id]?.rank) }
    }
    func testChildrenReorderBothDirectionsAndDropAfterExpandedBranch() throws {
        let events = fixture(), p = Projection(events: events)
        let event = try XCTUnwrap(Commands.prepare(move("a2", "a1", "before", ids: ["a1", "a2"]), projection: p, actor: "test").event)
        let next = Projection(events: events + [event])
        XCTAssertEqual(TaskOrdering.sorted(next.children(of: "task:a"), by: "manual").map(\.id), ["task:a2", "task:a1"])
        let reverse = try XCTUnwrap(Commands.prepare(move("a2", "a1", "after", ids: ["a2", "a1"], requestID: "reverse"), projection: next, actor: "test").event)
        let final = Projection(events: events + [event, reverse])
        XCTAssertEqual(TaskOrdering.sorted(final.children(of: "task:a"), by: "manual").map(\.id), ["task:a1", "task:a2"])
        XCTAssertEqual(TaskReordering.target(for: p.records["task:b"]!, over: p.records["task:a111"]!, records: p.records)?.id, "task:a")
        XCTAssertNil(TaskReordering.target(for: p.records["task:a"]!, over: p.records["task:a111"]!, records: p.records))
    }
    func testNativeListInsertionPreservesExpandedBranches() {
        let p = Projection(events: fixture())
        let rows = TaskOutline(matching: p.query(TaskFilter(listID: "list:content")), records: p.records, sort: "manual").rows().map(\.task)
        let b = p.records["task:b"]!, a = p.records["task:a"]!
        let afterBranch = TaskReordering.insertion(for: b, at: rows.firstIndex(where: { $0.id == b.id })!, rows: rows, records: p.records)
        XCTAssertEqual(afterBranch?.0.id, a.id); XCTAssertEqual(afterBranch?.1, .after)
        XCTAssertEqual(TaskReordering.insertion(for: b, at: 0, rows: rows, records: p.records)?.1, .before)
        XCTAssertNil(TaskReordering.insertion(for: a, at: 2, rows: rows, records: p.records))
        XCTAssertEqual(TaskReordering.insertion(for: a, at: rows.count, rows: rows, records: p.records)?.0.id, "task:c")
    }
    func testFilteredMoveKeepsOmittedSiblingSlotAndRejectsCrossParentOrProject() throws {
        let events = fixture(), p = Projection(events: events)
        let event = try XCTUnwrap(Commands.prepare(move("c", "a", "before", ids: ["a", "c"]), projection: p, actor: "test").event)
        let after = Projection(events: events + [event])
        XCTAssertEqual(TaskOrdering.sorted(after.tasks.filter { $0.parentID == nil && $0.listID == "list:content" }, by: "manual").map(\.id), ["task:c", "task:b", "task:a"])
        XCTAssertEqual(after.records["task:b"], p.records["task:b"])
        for request in [move("a1", "b1", "before", ids: ["a1", "b1"]), move("a", "other", "before", ids: ["a", "other"]), move("a", "b", "before", ids: ["a", "b", "a"])] {
            XCTAssertThrowsError(try Commands.prepare(request, projection: p, actor: "test"))
        }
    }
}
