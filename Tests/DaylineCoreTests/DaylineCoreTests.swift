import XCTest
@testable import DaylineCore

final class DaylineCoreTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    func date(_ text: String) -> Date { ExplicitDate.parseDate(text, calendar: calendar)! }
    func add(_ fields: [String: Value], requestID: String = "one", events: [ChangeEvent] = []) throws -> ChangeEvent {
        try Commands.prepare(AgentRequest(command: "task.add", requestID: requestID, fields: fields), projection: Projection(events: events), actor: "A", now: date("2026-09-13 08:00"), calendar: calendar).event!
    }
    func testConcurrentEditsConvergeAndPreserveIndependentFields() throws {
        let first = try add(["title": .string("Original")])
        let a = ChangeEvent(id: "a", actor: "Mac", clock: 2, changes: [Change(entity: "task:one", fields: ["title": .string("Updated on Mac")])])
        let b = ChangeEvent(id: "b", actor: "Phone", clock: 2, changes: [Change(entity: "task:one", fields: ["due": .date(date("2026-09-14"))])])
        let p = Projection(events: [b, a, first, a])
        XCTAssertEqual(p.records, Projection(events: [first, a, b]).records)
        XCTAssertEqual(p.tasks.first?.title, "Updated on Mac")
        XCTAssertEqual(p.tasks.first?.due, date("2026-09-14"))
        XCTAssertEqual(p.eventIDs.count, 3)
    }
    func testSameFieldConcurrentEditsResolveDeterministically() throws {
        let first = try add(["title": .string("Original")])
        let a = ChangeEvent(id: "a", actor: "A", clock: 2, changes: [Change(entity: "task:one", fields: ["title": .string("Mac")])])
        let b = ChangeEvent(id: "b", actor: "B", clock: 2, changes: [Change(entity: "task:one", fields: ["title": .string("Phone")])])
        XCTAssertEqual(Projection(events: [b, first, a]).tasks.first?.title, "Phone")
    }
    func testRetryIsIdempotentAndStaleRevisionIsRejected() throws {
        let first = try add(["title": .string("Task")])
        let p = Projection(events: [first])
        let retry = try Commands.prepare(AgentRequest(command: "task.add", requestID: "one", fields: ["title": .string("Task")]), projection: p, actor: "A")
        XCTAssertNil(retry.event)
        XCTAssertThrowsError(try Commands.prepare(AgentRequest(command: "task.update", id: "task:one", expectedRevision: "old", fields: ["title": .string("New")]), projection: p, actor: "A"))
    }
    func testRecurringCompletionOnTwoDevicesCreatesOneSuccessor() throws {
        let first = try add(["title": .string("Weekly"), "due": .date(date("2026-09-14 09:00")), "recurrence": .string("weekly")])
        let p = Projection(events: [first])
        let a = try Commands.prepare(AgentRequest(command: "task.complete", id: "task:one", requestID: "complete-mac"), projection: p, actor: "A", calendar: calendar).event!
        let b = try Commands.prepare(AgentRequest(command: "task.complete", id: "task:one", requestID: "complete-phone"), projection: p, actor: "B", calendar: calendar).event!
        let merged = Projection(events: [first, a, b])
        XCTAssertEqual(merged.tasks.count, 2)
        XCTAssertEqual(merged.tasks.filter { !$0.completed }.count, 1)
        XCTAssertEqual(merged.tasks.first { !$0.completed }?.due, date("2026-09-21 09:00"))
    }
    func testParentTrashRestoreAndCycleGuard() throws {
        let parent = try add(["title": .string("Parent")])
        let child = try add(["title": .string("Child"), "parentID": .string("task:one")], requestID: "child", events: [parent])
        let p = Projection(events: [parent, child])
        XCTAssertThrowsError(try Commands.prepare(AgentRequest(command: "task.update", id: "task:one", fields: ["parentID": .string("task:child")]), projection: p, actor: "A"))
        let trash = try Commands.prepare(AgentRequest(command: "task.trash", id: "task:one"), projection: p, actor: "A").event!
        let hidden = Projection(events: [parent, child, trash])
        XCTAssertTrue(hidden.query(TaskFilter()).isEmpty)
        XCTAssertEqual(hidden.query(TaskFilter(view: "trash")).count, 2)
        let restore = try Commands.prepare(AgentRequest(command: "task.restore", id: "task:one"), projection: hidden, actor: "A").event!
        XCTAssertEqual(Projection(events: [parent, child, trash, restore]).query(TaskFilter()).count, 2)
    }
    func testMonthEndWeekdaysLeapYearAndDST() {
        let jan = date("2026-01-31 09:00")
        let feb = Recurrence.next(after: jan, rule: "monthly", calendar: calendar, anchor: jan)!
        XCTAssertEqual(feb, date("2026-02-28 09:00"))
        XCTAssertEqual(Recurrence.next(after: feb, rule: "monthly", calendar: calendar, anchor: jan), date("2026-03-31 09:00"))
        XCTAssertEqual(Recurrence.next(after: date("2026-09-11 09:00"), rule: "weekdays", calendar: calendar), date("2026-09-14 09:00"))
        var ny = calendar; ny.timeZone = TimeZone(identifier: "America/New_York")!
        let before = ExplicitDate.parseDate("2026-03-07 09:00", calendar: ny)!
        let after = Recurrence.next(after: before, rule: "daily", calendar: ny)!
        XCTAssertEqual(ny.component(.hour, from: after), 9)
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3600)
    }
    func testLiteralTaskTitlesAndExplicitDates() throws {
        let title = "明天 09:30 写周报 #工作 !1"
        let p = Projection(events: [try add(["title": .string(title)])])
        XCTAssertEqual(p.tasks.first?.title, title)
        XCTAssertNil(p.tasks.first?.due)
        XCTAssertEqual(p.tasks.first?.tags, [])
        XCTAssertEqual(p.tasks.first?.priority, 0)
        XCTAssertNil(ExplicitDate.parseDate("明天"))
        XCTAssertNil(ExplicitDate.parseDate("2026-02-30", calendar: calendar))
    }
    func testTodayBoundaryAndOverdueVisibility() throws {
        let a = try add(["title": .string("Overdue"), "due": .date(date("2026-09-12"))])
        let b = try add(["title": .string("Today"), "due": .date(date("2026-09-13 23:59"))], requestID: "two", events: [a])
        let c = try add(["title": .string("Tomorrow"), "due": .date(date("2026-09-14"))], requestID: "three", events: [a,b])
        XCTAssertEqual(Projection(events: [a,b,c]).query(TaskFilter(view: "today"), now: date("2026-09-13 10:00"), calendar: calendar).count, 2)
    }
    func testMalformedMutationsAreRejectedBeforePersistence() throws {
        XCTAssertThrowsError(try add(["title": .string("")]))
        XCTAssertThrowsError(try add(["title": .string("x"), "priority": .number(5)]))
        XCTAssertThrowsError(try add(["title": .string("x"), "recurrence": .string("weekly")]))
        XCTAssertThrowsError(try add(["title": .string("x"), "due": .string("wrong")]))
        XCTAssertThrowsError(try add(["title": .string("x"), "completed": .flag(true)]))
        XCTAssertThrowsError(try add(["title": .string("x"), "listID": .string("missing")]))
    }
    func testArchiveCodingRoundTrip() throws {
        let first = try add(["title": .string("中文与 \"引号\""), "notes": .string("Line1\nLine2"), "tags": .strings(["工作"]), "due": .date(date("2026-09-13"))])
        let decoded = try JSONDecoder().decode(ChangeEvent.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(first, decoded)
    }
    func testValuesUsePlainJSONAndCanReadEarlyArchives() throws {
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(Value.string("task")), as: UTF8.self), "\"task\"")
        let legacy = Data(#"{"string":{"_0":"old task"}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Value.self, from: legacy), .string("old task"))
        XCTAssertEqual(try JSONDecoder().decode(Value.self, from: Data("null".utf8)), .null)
        XCTAssertEqual(try JSONDecoder().decode(Value.self, from: Data("true".utf8)), .flag(true))
    }
    func testUnchangedEditorDoesNotWriteAnEvent() throws {
        let first = try add(["title": .string("Task")])
        let response = try Commands.prepare(AgentRequest(command: "task.update", id: "task:one", fields: ["title": .string("Task")]), projection: Projection(events: [first]), actor: "A")
        XCTAssertNil(response.event)
    }
}
