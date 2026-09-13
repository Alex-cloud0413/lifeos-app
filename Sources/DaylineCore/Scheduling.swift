import Foundation

public enum Recurrence {
    public static let choices = ["none", "daily", "weekdays", "weekly", "biweekly", "monthly", "yearly"]
    public static func next(after date: Date, rule: String, calendar: Calendar = .current, anchor: Date? = nil) -> Date? {
        switch rule {
        case "daily": return calendar.date(byAdding: .day, value: 1, to: date)
        case "weekly": return calendar.date(byAdding: .day, value: 7, to: date)
        case "biweekly": return calendar.date(byAdding: .day, value: 14, to: date)
        case "weekdays":
            var next = date
            repeat { guard let d = calendar.date(byAdding: .day, value: 1, to: next) else { return nil }; next = d } while [1,7].contains(calendar.component(.weekday, from: next))
            return next
        case "monthly", "yearly":
            let component: Calendar.Component = rule == "monthly" ? .month : .year
            guard let candidate = calendar.date(byAdding: component, value: 1, to: date),
                  let range = calendar.range(of: .day, in: .month, for: candidate) else { return nil }
            let source = anchor ?? date
            var parts = calendar.dateComponents([.year, .month], from: candidate)
            parts.day = min(calendar.component(.day, from: source), range.count)
            let time = calendar.dateComponents([.hour, .minute, .second], from: date)
            parts.hour = time.hour; parts.minute = time.minute; parts.second = time.second
            return calendar.date(from: parts)
        default: return nil
        }
    }
}

public enum ExplicitDate {
    public static func parseDate(_ text: String, calendar: Calendar = .current) -> Date? {
        if let instant = DateCodec.parse(text) { return instant }
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = format; f.isLenient = false
            if let d = f.date(from: text), f.string(from: d) == text { return d }
        }
        return nil
    }
}
