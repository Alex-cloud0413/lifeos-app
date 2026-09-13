import XCTest
@testable import DaylineCore

final class ResponsivenessTests: XCTestCase {
    private func event(_ id: String, clock: Int, actor: String = "mac", fields: [String: Value]) -> ChangeEvent {
        ChangeEvent(id: id, actor: actor, clock: clock, createdAt: Date(timeIntervalSince1970: 100), changes: [Change(entity: "task:a", fields: fields)])
    }
    func testIncrementalAndLateRemoteEditsConvergeToFullReplay() throws {
        let a = event("a", clock: 1, fields: ["title": .string("Original"), "notes": .string("Old")])
        let c = event("c", clock: 3, fields: ["title": .string("Latest")])
        let b = event("b", clock: 2, actor: "phone", fields: ["notes": .string("Remote")])
        let d = event("d", clock: 3, actor: "phone", fields: ["priority": .number(3)])
        var index = EventIndex()
        for batch in [[a], [c], [b, d], [c, a]] { try index.merge(batch) }
        let full = Projection(events: [d, c, b, a])
        XCTAssertEqual(index.projection.records, full.records)
        XCTAssertEqual(index.projection.fieldRevisions, full.fieldRevisions)
        XCTAssertEqual(index.events.map(\.id), ["a", "b", "c", "d"])
        XCTAssertFalse(try index.merge([a, b]))
    }
    func testCollisionRejectsWholeIncomingBatchWithoutLosingSavedEvents() throws {
        let a = event("a", clock: 1, fields: ["title": .string("Original")])
        var index = EventIndex(); try index.merge([a])
        let next = event("b", clock: 2, fields: ["notes": .string("Incoming")])
        let collision = event("a", clock: 1, fields: ["title": .string("Conflict")])
        XCTAssertThrowsError(try index.merge([next, collision]))
        XCTAssertEqual(index.events, [a]); XCTAssertEqual(index.projection.records["task:a"]?.title, "Original")
        var empty = EventIndex(); XCTAssertThrowsError(try empty.merge([a, collision])); XCTAssertTrue(empty.events.isEmpty)
    }
    func testDateCachePreservesMillisecondsOffsetsAndLegacyWholeSeconds() {
        let precise = DateCodec.parse("2026-09-13T10:20:30.125Z")!
        XCTAssertEqual(DateCodec.format(precise), "2026-09-13T10:20:30.125Z")
        XCTAssertEqual(DateCodec.parse("2026-09-13T18:20:30.125+08:00"), precise)
        XCTAssertEqual(DateCodec.parse("2026-09-13T10:20:30Z")!.timeIntervalSince(precise), -0.125, accuracy: 0.0001)
        XCTAssertNil(DateCodec.parse("not a date"))
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            XCTAssertEqual(DateCodec.parse(DateCodec.format(precise)), precise)
        }
    }
}
