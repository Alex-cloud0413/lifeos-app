import Foundation

public enum TaskTimeScope: String, CaseIterable, Identifiable, Sendable {
    case today
    case nextSevenDays = "next7days"
    case month
    case quarter

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .today: return "今天"
        case .nextSevenDays: return "未来 7 天"
        case .month: return "本月"
        case .quarter: return "本季度"
        }
    }
    public var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .nextSevenDays: return "calendar"
        case .month: return "calendar.circle"
        case .quarter: return "calendar.badge.clock"
        }
    }

    /// Gregorian month/quarter boundaries in the device's time zone, not 30/90-day windows.
    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let start = local.startOfDay(for: now)
        let end: Date
        switch self {
        case .today: end = local.date(byAdding: .day, value: 1, to: start)!
        case .nextSevenDays: end = local.date(byAdding: .day, value: 7, to: start)!
        case .month: end = local.dateInterval(of: .month, for: now)!.end
        case .quarter:
            var parts = local.dateComponents([.year, .month], from: now)
            parts.month = ((parts.month! - 1) / 3) * 3 + 1
            parts.day = 1
            end = local.date(byAdding: .month, value: 3, to: local.date(from: parts)!)!
        }
        return DateInterval(start: start, end: end)
    }

    public func includes(_ due: Date, in interval: DateInterval) -> Bool {
        // Preserve today's existing overdue behavior. Other views start at today's midnight.
        due < interval.end && (self == .today || due >= interval.start)
    }
}
