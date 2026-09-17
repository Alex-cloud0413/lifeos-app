import Foundation

public enum Value: Codable, Equatable, Sendable {
    case string(String), number(Int), flag(Bool), strings([String]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .flag(value) }
        else if let value = try? c.decode(Int.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String].self) { self = .strings(value) }
        else {
            // Read early development archives without rewriting their immutable history.
            switch try LegacyValue(from: decoder) {
            case .string(let value): self = .string(value)
            case .number(let value): self = .number(value)
            case .flag(let value): self = .flag(value)
            case .strings(let value): self = .strings(value)
            case .null: self = .null
            }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .flag(let value): try c.encode(value)
        case .strings(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
    private enum LegacyValue: Codable { case string(String), number(Int), flag(Bool), strings([String]), null }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Int? { if case .number(let v) = self { return v }; return nil }
    public var flag: Bool? { if case .flag(let v) = self { return v }; return nil }
    public var strings: [String]? { if case .strings(let v) = self { return v }; return nil }
    public static func date(_ date: Date?) -> Value { date.map { .string(DateCodec.format($0)) } ?? .null }
    public var date: Date? { string.flatMap(DateCodec.parse) }
}

public enum DateCodec {
    // Formatters are expensive to construct; keep them behind one lock for CLI and UI callers.
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        let fractional = ISO8601DateFormatter()
        let whole = ISO8601DateFormatter()
        let dates = NSCache<NSString, NSDate>()
        init() {
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            dates.countLimit = 4096
        }
    }
    private static let storage = Storage()
    public static func format(_ date: Date) -> String {
        storage.lock.lock(); defer { storage.lock.unlock() }
        return storage.fractional.string(from: date)
    }
    public static func parse(_ string: String) -> Date? {
        if let cached = storage.dates.object(forKey: string as NSString) { return cached as Date }
        storage.lock.lock(); defer { storage.lock.unlock() }
        guard let date = storage.fractional.date(from: string) ?? storage.whole.date(from: string) else { return nil }
        storage.dates.setObject(date as NSDate, forKey: string as NSString)
        return date
    }
}

public struct Change: Codable, Equatable, Sendable {
    public var entity: String
    public var kind: String
    public var fields: [String: Value]
    public init(entity: String, kind: String = "task", fields: [String: Value]) {
        self.entity = entity; self.kind = kind; self.fields = fields
    }
}

/// Immutable sync units. Field-level ordering is Lamport clock, actor, then event ID.
public struct ChangeEvent: Codable, Equatable, Sendable, Identifiable {
    public var schema = 1
    public var id: String
    public var actor: String
    public var clock: Int
    public var createdAt: Date
    public var changes: [Change]
    public init(id: String = UUID().uuidString, actor: String, clock: Int, createdAt: Date = Date(), changes: [Change]) {
        self.id = id; self.actor = actor; self.clock = clock; self.createdAt = createdAt; self.changes = changes
    }
}

public struct Record: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var fields: [String: Value]
    public var revision: String
    public subscript(_ field: String) -> Value { fields[field] ?? .null }
    public var title: String { self["title"].string ?? "" }
    public var notes: String { self["notes"].string ?? "" }
    public var tags: [String] { self["tags"].strings ?? [] }
    public var priority: Int { self["priority"].number ?? 0 }
    public var listID: String { self["listID"].string ?? "inbox" }
    public var directionID: String? { self["directionID"].string }
    public var parentID: String? { self["parentID"].string }
    public var due: Date? { self["due"].date }
    public var end: Date? { self["end"].date }
    public var completed: Bool { self["completed"].flag ?? false }
    public var trashed: Bool { self["trashed"].flag ?? false }
    public var purged: Bool { self["purged"].flag ?? false }
    public var archived: Bool { self["archived"].flag ?? false }
    public var allDay: Bool { self["allDay"].flag ?? true }
    public var recurrence: String { self["recurrence"].string ?? "none" }
    public var status: String { completed ? "done" : (self["status"].string ?? "todo") }
    public var color: String { self["color"].string ?? "blue" }
    public var isNote: Bool { self["itemType"].string == "note" }
    public var pinned: Bool { self["pinned"].flag ?? false }
    public var rank: Int { self["rank"].number ?? 0 }
    public var progress: Int { completed ? 100 : (self["progress"].number ?? 0) }
    public var section: String { self["section"].string ?? "" }
    public var sections: [String] { self["sections"].strings ?? [] }
    public var createdAt: Date { self["createdAt"].date ?? .distantPast }
}

public struct Projection: Sendable {
    public private(set) var records: [String: Record] = [:]
    public private(set) var eventIDs: Set<String> = []
    public private(set) var clock = 0
    public private(set) var fieldRevisions: [String: [String: String]] = [:]
    public init(events: [ChangeEvent] = []) {
        for event in events.sorted(by: Self.precedes) { apply(event) }
    }
    public mutating func apply(_ event: ChangeEvent) {
        guard event.schema == 1, eventIDs.insert(event.id).inserted else { return }
        clock = max(clock, event.clock)
        for change in event.changes {
            var r = records[change.entity] ?? Record(id: change.entity, kind: change.kind, fields: [:], revision: "")
            guard r.kind == change.kind else { continue }
            // A terminal tombstone wins over later edits, restores and older backup imports.
            guard !r.purged else { continue }
            if change.fields["purged"]?.flag == true {
                r.fields = ["purged": .flag(true), "trashed": .flag(true)]
                r.revision = event.id; records[r.id] = r
                fieldRevisions[r.id] = ["purged": event.id]
                continue
            }
            r.fields.merge(change.fields) { _, new in new }; r.revision = event.id
            records[r.id] = r
            for key in change.fields.keys { fieldRevisions[r.id, default: [:]][key] = event.id }
        }
    }
    static func precedes(_ a: ChangeEvent, _ b: ChangeEvent) -> Bool {
        if a.clock != b.clock { return a.clock < b.clock }
        if a.actor != b.actor { return a.actor < b.actor }
        return a.id < b.id
    }
    public var tasks: [Record] { records.values.filter { $0.kind == "task" && !$0.title.isEmpty }.sorted { a, b in
        if a.priority != b.priority { return a.priority > b.priority }
        if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
        return a.id < b.id
    } }
    public var directions: [Record] { records.values.filter { $0.kind == "direction" && !$0.trashed && !isPurged($0) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    public var templates: [Record] { records.values.filter { $0.kind == "template" && !$0.trashed && !isPurged($0) }.sorted { $0.title < $1.title } }
    public var lists: [Record] { records.values.filter { $0.kind == "list" && !$0.trashed && !isPurged($0) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    public var filters: [Record] { records.values.filter { $0.kind == "filter" && !$0.trashed && !isPurged($0) }.sorted { $0.title < $1.title } }
    public func isPurged(_ record: Record) -> Bool {
        var pending = [record.id]; var seen: Set<String> = []
        while let id = pending.popLast() {
            guard seen.insert(id).inserted, let item = records[id] else { continue }
            if item.purged { return true }
            if let parent = item.parentID { pending.append(parent) }
            if item.kind == "task", item.listID != "inbox" { pending.append(item.listID) }
            if let direction = item.directionID { pending.append(direction) }
        }
        return false
    }
    public var trashRecords: [Record] {
        records.values.filter { !isPurged($0) && ($0.trashed || ($0.kind == "task" && isHidden($0))) }.sorted { $0.id < $1.id }
    }
    public func visibleHistory(_ events: [ChangeEvent]) -> [ChangeEvent] {
        events.compactMap { event in
            var copy = event
            copy.changes.removeAll { records[$0.entity].map(isPurged) ?? false }
            return copy.changes.isEmpty ? nil : copy
        }
    }
    public func isHidden(_ task: Record) -> Bool {
        if isPurged(task) { return true }
        if task.trashed { return true }
        var current = task.parentID; var seen: Set<String> = [task.id]
        while let id = current {
            guard seen.insert(id).inserted else { return true }
            guard let parent = records[id] else { return false }
            if parent.trashed { return true }
            current = parent.parentID
        }
        return false
    }
    public func children(of id: String) -> [Record] { tasks.filter { $0.parentID == id && !isHidden($0) } }
    public func query(_ filter: TaskFilter, now: Date = Date(), calendar: Calendar = .current) -> [Record] {
        let timeScope = TaskTimeScope(rawValue: filter.view)
        let timeInterval = timeScope?.interval(now: now, calendar: calendar)
        return tasks.filter { task in
            guard !isPurged(task) else { return false }
            if let direction = filter.directionID, records[task.listID]?.directionID != direction { return false }
            guard filter.matchesConditions(task) else { return false }
            let hidden = isHidden(task)
            if filter.view == "trash" { return hidden && filter.matchesText(task) }
            guard !hidden else { return false }
            if filter.view == "completed" { return !task.isNote && task.completed && filter.matchesText(task) }
            if filter.view == "notes" { guard task.isNote else { return false } }
            else if filter.itemType == "task" && task.isNote { return false }
            else if filter.itemType == "note" && !task.isNote { return false }
            guard filter.includeCompleted || !task.completed else { return false }
            if let list = records[task.listID], list.archived && filter.listID != list.id { return false }
            let today = calendar.startOfDay(for: now)
            if let timeScope, let timeInterval {
                guard let due = task.due, timeScope.includes(due, in: timeInterval) else { return false }
            } else if filter.view == "upcoming" {
                guard let due = task.due, due < calendar.date(byAdding: .day, value: 7, to: today)! else { return false }
            } else if filter.view == "tomorrow" {
                guard let due = task.due, calendar.isDate(due, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today)!) else { return false }
            } else if filter.view == "undated" && task.due != nil { return false }
            return filter.matchesText(task)
        }
    }
}

public struct TaskFilter: Codable, Sendable {
    public var view: String
    public var listID: String?
    public var tag: String?
    public var priority: Int?
    public var search: String
    public var includeCompleted: Bool
    public var directionID: String?
    public var listIDs: [String] = []
    public var tags: [String] = []
    public var excludedTags: [String] = []
    public var excludedLists: [String] = []
    public var matchAny = false
    public var dueFrom: Date?
    public var dueThrough: Date?
    public var itemType = "task"
    public var pinnedOnly = false
    public init(view: String = "all", listID: String? = nil, tag: String? = nil, priority: Int? = nil, search: String = "", includeCompleted: Bool = false) {
        self.view = view; self.listID = listID; self.tag = tag; self.priority = priority; self.search = search; self.includeCompleted = includeCompleted
    }
    private enum CodingKeys: String, CodingKey { case directionID, view, listID, tag, priority, search, includeCompleted, listIDs, tags, excludedTags, excludedLists, matchAny, dueFrom, dueThrough, itemType, pinnedOnly }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        directionID = try c.decodeIfPresent(String.self, forKey: .directionID)
        view = try c.decodeIfPresent(String.self, forKey: .view) ?? "all"
        listID = try c.decodeIfPresent(String.self, forKey: .listID)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        search = try c.decodeIfPresent(String.self, forKey: .search) ?? ""
        includeCompleted = try c.decodeIfPresent(Bool.self, forKey: .includeCompleted) ?? false
        listIDs = try c.decodeIfPresent([String].self, forKey: .listIDs) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        excludedTags = try c.decodeIfPresent([String].self, forKey: .excludedTags) ?? []
        excludedLists = try c.decodeIfPresent([String].self, forKey: .excludedLists) ?? []
        matchAny = try c.decodeIfPresent(Bool.self, forKey: .matchAny) ?? false
        dueFrom = try c.decodeIfPresent(Date.self, forKey: .dueFrom)
        dueThrough = try c.decodeIfPresent(Date.self, forKey: .dueThrough)
        itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "task"
        pinnedOnly = try c.decodeIfPresent(Bool.self, forKey: .pinnedOnly) ?? false
    }
    public func matchesConditions(_ r: Record) -> Bool {
        guard !excludedLists.contains(r.listID), Set(excludedTags).isDisjoint(with: r.tags) else { return false }
        if pinnedOnly && !r.pinned { return false }
        if let from = dueFrom, (r.due ?? .distantPast) < from { return false }
        if let through = dueThrough, (r.due ?? .distantFuture) > through { return false }
        var checks: [Bool] = []
        if let id = listID { checks.append(r.listID == id) }
        if !listIDs.isEmpty { checks.append(listIDs.contains(r.listID)) }
        if let tag { checks.append(r.tags.contains(tag)) }
        checks.append(contentsOf: tags.map { r.tags.contains($0) })
        if let priority { checks.append(r.priority == priority) }
        return checks.isEmpty || (matchAny ? checks.contains(true) : checks.allSatisfy { $0 })
    }
    func matchesText(_ r: Record) -> Bool {
        search.isEmpty || ([r.title, r.notes] + r.tags).joined(separator: " ").localizedCaseInsensitiveContains(search)
    }
}
