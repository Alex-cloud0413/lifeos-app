import Foundation

/// Cache immutable events. Append normal local edits; replay only when remote history arrives out of order.
public struct EventIndex: Sendable {
    public private(set) var events: [ChangeEvent] = []
    public private(set) var projection = Projection()
    private var known: [String: ChangeEvent] = [:]
    public init() {}
    public func event(_ id: String) -> ChangeEvent? { known[id] }

    @discardableResult public mutating func merge(_ incoming: [ChangeEvent]) throws -> Bool {
        var additions: [String: ChangeEvent] = [:]
        // Validate the entire batch before changing the visible state.
        for event in incoming {
            guard event.schema == 1, event.clock > 0, !event.id.isEmpty else { throw CommandError("corrupt_event", "操作记录格式无效。") }
            if let existing = known[event.id] ?? additions[event.id] {
                guard existing == event else { throw CommandError("event_collision", "同一操作 ID 出现不同内容，已停止合并。") }
            } else { additions[event.id] = event }
        }
        guard !additions.isEmpty else { return false }
        let ordered = additions.values.sorted(by: Projection.precedes)
        let appendOnly = events.last.map { Projection.precedes($0, ordered[0]) } ?? true
        known.merge(additions) { old, _ in old }
        events.append(contentsOf: ordered)
        if appendOnly { for event in ordered { projection.apply(event) } }
        else {
            events.sort(by: Projection.precedes)
            projection = Projection(events: events)
        }
        return true
    }
}
