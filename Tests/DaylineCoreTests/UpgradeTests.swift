import XCTest
@testable import DaylineCore

final class UpgradeTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    func date(_ text: String) -> Date { ExplicitDate.parseDate(text, calendar: calendar)! }
    @discardableResult func apply(_ command: String, _ id: String? = nil, fields: [String: Value] = [:], events: inout [ChangeEvent], request: String = UUID().uuidString) throws -> AgentResponse {
        let prepared = try Commands.prepare(AgentRequest(command: command, id: id, requestID: request, fields: fields), projection: Projection(events: events), actor: "test", now: date("2026-09-13 12:00"), calendar: calendar)
        if let e = prepared.event { events.append(e) }
        return prepared.response
    }
    func testBatchIsAtomicAndPreservesDurations() throws {
        var events: [ChangeEvent] = []
        try apply("task.add", fields: ["title": .string("A"), "due": .date(date("2026-09-13 09:00")), "end": .date(date("2026-09-13 11:00"))], events: &events, request: "a")
        try apply("task.add", fields: ["title": .string("B")], events: &events, request: "b")
        let original = events
        XCTAssertThrowsError(try apply("task.batch", fields: ["ids": .strings(["task:a", "task:missing"]), "priority": .number(3)], events: &events))
        XCTAssertEqual(events, original)
        try apply("task.batch", fields: ["ids": .strings(["task:a", "task:b"]), "due": .date(date("2026-09-14 10:00"))], events: &events)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(Projection(events: events).records["task:a"]?.end, date("2026-09-14 12:00"))
    }
    func testTemplatesCopyTreeRichTextAndShiftRelativeDates() throws {
        var events: [ChangeEvent] = []
        try apply("task.add", fields: ["title": .string("父"), "notes": .string("正文"), "richNotes": .string("RTF-test"), "due": .date(date("2026-09-13 09:00"))], events: &events, request: "a")
        try apply("task.add", fields: ["title": .string("子"), "parentID": .string("task:a"), "due": .date(date("2026-09-15 10:00"))], events: &events, request: "b")
        let template = try apply("template.save", "task:a", events: &events).records[0]
        let copied = try apply("template.use", template.id, fields: ["anchor": .date(date("2026-10-01"))], events: &events).records[0]
        let p = Projection(events: events)
        XCTAssertEqual(copied.due, date("2026-10-01 09:00")); XCTAssertEqual(copied["richNotes"].string, "RTF-test")
        XCTAssertEqual(p.children(of: copied.id)[0].due, date("2026-10-03 10:00"))
        let undated = try apply("template.use", template.id, events: &events).records[0]
        XCTAssertNil(undated.due)
        XCTAssertNil(Projection(events: events).children(of: undated.id)[0].due)
    }
    func testFiltersExcludeBeforeORAndRetainLegacyQueries() throws {
        var events: [ChangeEvent] = []
        try apply("task.add", fields: ["title": .string("A"), "tags": .strings(["工作", "暂缓"]), "priority": .number(3)], events: &events, request: "a")
        try apply("task.add", fields: ["title": .string("B"), "tags": .strings(["工作"])], events: &events, request: "b")
        var f = TaskFilter(priority: 3); f.tags = ["工作"]; f.matchAny = true; f.excludedTags = ["暂缓"]
        XCTAssertEqual(Projection(events: events).query(f).map(\.title), ["B"])
        let old = try JSONDecoder().decode(TaskFilter.self, from: Data("{\"tag\":\"工作\"}".utf8))
        XCTAssertEqual(Projection(events: events).query(old).count, 2)
    }
    func testUndoPreservesLaterIndependentChangesButRejectsSameField() throws {
        var events: [ChangeEvent] = []
        try apply("task.add", fields: ["title": .string("A")], events: &events, request: "a")
        try apply("task.update", "task:a", fields: ["title": .string("B")], events: &events, request: "title-edit")
        try apply("task.update", "task:a", fields: ["notes": .string("new notes")], events: &events)
        let undo = try History.undo("title-edit", events: events, requestID: "undo", actor: "test")
        let p = Projection(events: events + [undo]); XCTAssertEqual(p.records["task:a"]?.title, "A"); XCTAssertEqual(p.records["task:a"]?.notes, "new notes")
        XCTAssertThrowsError(try History.undo("a", events: events, requestID: "undo-create", actor: "test"))
        try apply("task.update", "task:a", fields: ["title": .string("C")], events: &events)
        XCTAssertThrowsError(try History.undo("title-edit", events: events, requestID: "undo-title", actor: "test"))
    }
    func testOrderingAndNoteConversionAndProgress() throws {
        var events: [ChangeEvent] = []
        try apply("task.add", fields: ["title": .string("Z"), "progress": .number(65)], events: &events, request: "a")
        try apply("task.add", fields: ["title": .string("A"), "pinned": .flag(true)], events: &events, request: "b")
        try apply("task.reorder", fields: ["ids": .strings(["task:a", "task:b"])], events: &events)
        XCTAssertEqual(TaskOrdering.sorted(Projection(events: events).tasks, by: "manual").first?.id, "task:b")
        try apply("task.convert", "task:a", fields: ["itemType": .string("note")], events: &events)
        XCTAssertEqual(Projection(events: events).query(TaskFilter()).count, 1)
        XCTAssertEqual(Projection(events: events).query(TaskFilter(view: "notes")).first?.id, "task:a")
        XCTAssertThrowsError(try apply("task.complete", "task:a", events: &events))
        XCTAssertThrowsError(try apply("task.update", "task:b", fields: ["progress": .number(101)], events: &events))
    }
    func testCalendarOverlapsBoundaryAndQuarterHourSnap() throws {
        var events: [ChangeEvent] = []
        for (id, start, end) in [("a", "09:00", "11:00"), ("b", "10:00", "12:00"), ("c", "12:00", "13:00")] {
            try apply("task.add", fields: ["title": .string(id), "allDay": .flag(false), "due": .date(date("2026-09-13 " + start)), "end": .date(date("2026-09-13 " + end))], events: &events, request: id)
        }
        let blocks = CalendarLayout.blocks(Projection(events: events).tasks, day: date("2026-09-13"), calendar: calendar)
        XCTAssertEqual(blocks.map(\.lanes), [2, 2, 1]); XCTAssertEqual(blocks.map(\.lane), [0, 1, 0]); XCTAssertEqual(blocks[0].start, 540)
        XCTAssertEqual(CalendarLayout.snap(minutes: 23), 30); XCTAssertEqual(CalendarLayout.snap(minutes: -23), -30)
        XCTAssertTrue(CalendarLayout.blocks(Projection(events: events).tasks, day: date("2026-09-14"), calendar: calendar).isEmpty)
    }
    func testLinksRoundTripReservedCharactersAndRejectOtherSchemes() {
        let id = "task:abc/中文@time?&=日程"
        XCTAssertEqual(TaskLink.id(from: TaskLink.url(id)), id)
        XCTAssertNil(TaskLink.id(from: URL(string: "https://example.com/task?id=task:1")!))
    }
}
