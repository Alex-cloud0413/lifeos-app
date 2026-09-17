import XCTest
@testable import DaylineCore

final class TaskTimeScopeTests: XCTestCase {
    func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar()).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func task(_ id: String, due: Date? = nil, fields: [String: Value] = [:]) -> Change {
        var values: [String: Value] = ["title": .string(id), "listID": .string("list:active"), "due": .date(due)]
        values.merge(fields) { _, new in new }
        return Change(entity: "task:" + id, fields: values)
    }
    func projection(_ changes: [Change]) -> Projection {
        Projection(events: [ChangeEvent(actor: "test", clock: 1, changes: [
            Change(entity: "list:active", kind: "list", fields: ["title": .string("专项")]),
            Change(entity: "list:archived", kind: "list", fields: ["title": .string("归档"), "archived": .flag(true)])
        ] + changes)])
    }
    func testTodayPreservesOverdueAndExcludesTomorrow() {
        let now = date(2026, 9, 18, 12)
        let range = TaskTimeScope.today.interval(now: now, calendar: calendar())
        XCTAssertEqual(range.start, date(2026, 9, 18))
        XCTAssertEqual(range.end, date(2026, 9, 19))
        XCTAssertTrue(TaskTimeScope.today.includes(date(2026, 8, 1), in: range))
        XCTAssertTrue(TaskTimeScope.today.includes(range.end.addingTimeInterval(-1), in: range))
        XCTAssertFalse(TaskTimeScope.today.includes(range.end, in: range))
    }
    func testSevenDaysIncludesTodayAndCrossesYearWithoutOverdue() {
        let range = TaskTimeScope.nextSevenDays.interval(now: date(2026, 12, 29, 23), calendar: calendar())
        XCTAssertEqual(range.start, date(2026, 12, 29))
        XCTAssertEqual(range.end, date(2027, 1, 5))
        XCTAssertFalse(TaskTimeScope.nextSevenDays.includes(range.start.addingTimeInterval(-1), in: range))
        XCTAssertTrue(TaskTimeScope.nextSevenDays.includes(range.start, in: range))
        XCTAssertTrue(TaskTimeScope.nextSevenDays.includes(range.end.addingTimeInterval(-1), in: range))
        XCTAssertFalse(TaskTimeScope.nextSevenDays.includes(range.end, in: range))
    }
    func testMonthUsesActualCalendarEndIncludingLeapYear() {
        for (year, month, day, nextMonth) in [(2028, 2, 28, 3), (2026, 4, 30, 5), (2026, 9, 18, 10)] {
            let range = TaskTimeScope.month.interval(now: date(year, month, day, 12), calendar: calendar())
            XCTAssertEqual(range.start, date(year, month, day))
            XCTAssertEqual(range.end, date(year, nextMonth, 1))
        }
        XCTAssertEqual(TaskTimeScope.month.interval(now: date(2026, 12, 31), calendar: calendar()).end, date(2027, 1, 1))
    }
    func testAllNaturalQuarterBoundariesAndYearRollover() {
        for month in 1...12 {
            let range = TaskTimeScope.quarter.interval(now: date(2026, month, 18), calendar: calendar())
            let endMonth = ((month - 1) / 3 + 1) * 3 + 1
            XCTAssertEqual(range.start, date(2026, month, 18))
            XCTAssertEqual(range.end, endMonth == 13 ? date(2027, 1, 1) : date(2026, endMonth, 1))
            XCTAssertFalse(TaskTimeScope.quarter.includes(range.end, in: range))
        }
    }
    func testSevenDaysUsesCalendarDaysAcrossDaylightSaving() {
        let la = calendar("America/Los_Angeles")
        let spring = TaskTimeScope.nextSevenDays.interval(now: date(2026, 3, 7, 12, calendar: la), calendar: la)
        XCTAssertEqual(spring.end, date(2026, 3, 14, calendar: la))
        XCTAssertEqual(spring.duration, 167 * 3600)
        let fall = TaskTimeScope.nextSevenDays.interval(now: date(2026, 10, 31, 12, calendar: la), calendar: la)
        XCTAssertEqual(fall.end, date(2026, 11, 7, calendar: la))
        XCTAssertEqual(fall.duration, 169 * 3600)
    }
    func testTimeZoneAndNonGregorianUserCalendarKeepNaturalQuarter() {
        let instant = date(2026, 10, 1, 1)
        XCTAssertEqual(TaskTimeScope.quarter.interval(now: instant, calendar: calendar()).end, date(2027, 1, 1))
        let la = calendar("America/Los_Angeles")
        XCTAssertEqual(TaskTimeScope.quarter.interval(now: instant, calendar: la).end, date(2026, 10, 1, calendar: la))
        var alternative = Calendar(identifier: .hebrew); alternative.timeZone = calendar().timeZone
        XCTAssertEqual(TaskTimeScope.quarter.interval(now: instant, calendar: alternative).end, date(2027, 1, 1))
    }
    func testQueryFiltersPendingScheduledTasksAndRetainsParentContext() throws {
        let due = date(2026, 9, 18)
        let p = projection([
            task("parent"), task("child", due: due, fields: ["parentID": .string("task:parent")]),
            task("done", due: due, fields: ["completed": .flag(true)]),
            task("trash", due: due, fields: ["trashed": .flag(true)]),
            task("archived", due: due, fields: ["listID": .string("list:archived")]),
            task("note", due: due, fields: ["itemType": .string("note")]),
            task("undated"), task("yesterday", due: date(2026, 9, 17)),
            task("nextMonth", due: date(2026, 10, 1))
        ])
        for scope in TaskTimeScope.allCases {
            let f = TaskFilter(view: scope.rawValue)
            let matches = p.query(f, now: due, calendar: calendar())
            XCTAssertEqual(Set(matches.map(\.id)), scope == .today ? ["task:child", "task:yesterday"] : ["task:child"])
            let result = try Commands.prepare(AgentRequest(command: "task.list", filter: f), projection: p, actor: "agent", now: due, calendar: calendar())
            XCTAssertNil(result.event)
            XCTAssertEqual(Set(result.response.records.map(\.id)), Set(matches.map(\.id)))
        }
        let outline = TaskOutline(matching: p.query(TaskFilter(view: "month"), now: due, calendar: calendar()), records: p.records, sort: "date").rows()
        XCTAssertEqual(outline.map(\.id), ["task:parent", "task:child"])
        XCTAssertEqual(outline.map(\.isMatch), [false, true])
        XCTAssertEqual(outline.map(\.depth), [0, 1])
    }
    func testPhoneTaskOpensWithinEachTimeViewWithoutDirectionDetour() {
        let p = projection([task("child", due: date(2026, 9, 18))])
        for scope in TaskTimeScope.allCases {
            let page = TaskNavigation.pages(for: scope.rawValue, records: p.records)
            let path = TaskNavigation.opening("task:child", from: page, projection: p)
            XCTAssertEqual(path, [.page(scope.rawValue), .task("task:child")])
            XCTAssertEqual(Array(path.dropLast()), page)
        }
    }
}
