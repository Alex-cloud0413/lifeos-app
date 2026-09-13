import XCTest
@testable import DaylineCore

final class TrashTests: XCTestCase {
    private func event(_ id: String, _ clock: Int, _ changes: [Change], actor: String = "Mac") -> ChangeEvent {
        ChangeEvent(id: id, actor: actor, clock: clock, changes: changes)
    }
    private var initial: [ChangeEvent] {
        [event("initial", 1, [
            Change(entity: "task:root", fields: ["title": .string("旧任务"), "notes": .string("原文"), "trashed": .flag(true)]),
            Change(entity: "task:child", fields: ["title": .string("子任务"), "parentID": .string("task:root")]),
            Change(entity: "task:leaf", fields: ["title": .string("多层子任务"), "parentID": .string("task:child")]),
            Change(entity: "task:active", fields: ["title": .string("保留任务")]),
            Change(entity: "list:archived", kind: "list", fields: ["title": .string("归档专项"), "archived": .flag(true)]),
            Change(entity: "task:archive", fields: ["title": .string("归档任务"), "listID": .string("list:archived")]),
            Change(entity: "list:old", kind: "list", fields: ["title": .string("已删专项"), "trashed": .flag(true)])
        ])]
    }
    private func empty(_ p: Projection, id: String = "empty") throws -> PreparedCommand {
        try Commands.prepare(AgentRequest(command: "trash.empty", requestID: id, fields: [
            "confirm": .flag(true), "ids": .strings(p.trashRecords.map(\.id)), "revisions": .strings(p.trashRecords.map(\.revision))
        ]), projection: p, actor: "Mac")
    }
    func testEmptyRemovesWholeSubtreeAndDeletedProjectsPreservesActiveAndArchived() throws {
        var p = Projection(events: initial)
        let active = p.records["task:active"], archived = p.records["task:archive"]
        p.apply(try empty(p).event!)
        XCTAssertTrue(p.trashRecords.isEmpty)
        XCTAssertTrue(p.query(TaskFilter(view: "trash")).isEmpty)
        for id in ["task:root", "task:child", "task:leaf", "list:old"] {
            XCTAssertTrue(p.records[id]!.purged)
            XCTAssertNil(p.records[id]?.fields["title"])
            XCTAssertThrowsError(try Commands.prepare(AgentRequest(command: "task.restore", id: id), projection: p, actor: "Mac"))
        }
        XCTAssertEqual(p.records["task:active"], active)
        XCTAssertEqual(p.records["task:archive"], archived)
        XCTAssertEqual(p.lists.map(\.id), ["list:archived"])
    }
    func testConfirmationAndExactTrashSnapshotRequired() throws {
        let p = Projection(events: initial)
        XCTAssertThrowsError(try Commands.prepare(AgentRequest(command: "trash.empty"), projection: p, actor: "Mac"))
        var changed = p
        changed.apply(event("new-trash", 2, [Change(entity: "task:active", fields: ["trashed": .flag(true)])]))
        let request = AgentRequest(command: "trash.empty", fields: ["confirm": .flag(true), "ids": .strings(p.trashRecords.map(\.id)), "revisions": .strings(p.trashRecords.map(\.revision))])
        XCTAssertThrowsError(try Commands.prepare(request, projection: changed, actor: "Mac"))
        changed = p
        changed.apply(event("restored", 2, [Change(entity: "task:root", fields: ["trashed": .flag(false)])]))
        XCTAssertThrowsError(try Commands.prepare(request, projection: changed, actor: "Mac"))
    }
    func testOfflineEditsAndLaterArrivingChildCannotResurrectPurgedParent() throws {
        let p = Projection(events: initial), purge = try empty(p).event!
        let offline = event("offline", purge.clock + 10, [
            Change(entity: "task:root", fields: ["title": .string("旧端修改"), "trashed": .flag(false), "purged": .flag(false)]),
            Change(entity: "task:offline-child", fields: ["title": .string("离线子任务"), "parentID": .string("task:root")])
        ], actor: "Phone")
        let merged = Projection(events: initial + [offline, purge])
        XCTAssertTrue(merged.records["task:root"]!.purged)
        XCTAssertTrue(merged.isPurged(merged.records["task:offline-child"]!))
        XCTAssertTrue(merged.query(TaskFilter(view: "trash")).isEmpty)
        XCTAssertEqual(merged.query(TaskFilter()).map(\.id), ["task:active"])
        var index = EventIndex()
        try index.merge(initial + [offline]); try index.merge([purge])
        XCTAssertEqual(index.projection.records, merged.records)
        XCTAssertFalse(index.projection.visibleHistory(index.events).flatMap(\.changes).contains { $0.entity == "task:root" || $0.entity == "task:offline-child" })
    }
    func testCannotUndoPurgeOrOriginalEditsAndRetryDoesNotClearNewTrash() throws {
        let p = Projection(events: initial), prepared = try empty(p)
        let events = initial + [prepared.event!]
        XCTAssertThrowsError(try History.undo("empty", events: events, requestID: "undo", actor: "Mac"))
        XCTAssertThrowsError(try History.undo("initial", events: events, requestID: "undo", actor: "Mac"))
        var next = Projection(events: events)
        next.apply(event("new-trash", 100, [Change(entity: "task:active", fields: ["trashed": .flag(true)])]))
        XCTAssertNil(try empty(next).event)
        XCTAssertEqual(next.trashRecords.map(\.id), ["task:active"])
    }
    func testEmptyTrashIsNoOp() throws {
        var p = Projection()
        let attempt = try empty(p).event!
        XCTAssertTrue(attempt.changes.isEmpty)
        p.apply(attempt)
        p.apply(event("later", 2, [Change(entity: "task:later", fields: ["title": .string("后来删除"), "trashed": .flag(true)])]))
        XCTAssertNil(try empty(p).event)
        XCTAssertEqual(p.trashRecords.map(\.id), ["task:later"])
    }
}
