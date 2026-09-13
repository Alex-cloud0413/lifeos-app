import Foundation

public struct TimeBlock: Identifiable, Sendable {
    public let task: Record
    public var id: String { task.id }
    public var start: Double
    public var end: Double
    public var lane: Int = 0
    public var lanes: Int = 1
}
public enum CalendarLayout {
    public static func blocks(_ tasks: [Record], day: Date, calendar: Calendar = .current) -> [TimeBlock] {
        let start = calendar.startOfDay(for: day), next = calendar.date(byAdding: .day, value: 1, to: start)!
        var blocks = tasks.compactMap { task -> TimeBlock? in
            guard !task.allDay, !task.isNote, let due = task.due else { return nil }
            let end = task.end ?? due.addingTimeInterval(3600)
            guard due < next, end > start else { return nil }
            func minute(_ date: Date) -> Double { let c = calendar.dateComponents([.hour, .minute], from: date); return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) }
            let lower = due <= start ? 0 : minute(due)
            let upper = end >= next ? 1440 : minute(end)
            return TimeBlock(task: task, start: lower, end: max(lower + 1, upper))
        }.sorted { $0.start == $1.start ? ($0.end == $1.end ? $0.id < $1.id : $0.end > $1.end) : $0.start < $1.start }
        var lanes: [Double] = []; var group: [Int] = []; var groupEnd = -1.0
        func closeGroup() { for index in group { blocks[index].lanes = max(1, lanes.count) }; group = []; lanes = [] }
        for index in blocks.indices {
            if blocks[index].start >= groupEnd { closeGroup(); groupEnd = -1 }
            let lane = lanes.firstIndex(where: { $0 <= blocks[index].start }) ?? lanes.count
            if lane == lanes.count { lanes.append(blocks[index].end) } else { lanes[lane] = blocks[index].end }
            blocks[index].lane = lane; group.append(index); groupEnd = max(groupEnd, blocks[index].end)
        }
        closeGroup(); return blocks
    }
    public static func snap(minutes: Double) -> Int { Int((minutes / 15).rounded()) * 15 }
}
