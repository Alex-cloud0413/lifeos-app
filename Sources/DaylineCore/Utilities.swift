import Foundation

public enum TaskLink {
    public static func url(_ id: String) -> URL {
        var c = URLComponents(); c.scheme = AppConfiguration.urlScheme; c.host = "task"; c.queryItems = [URLQueryItem(name: "id", value: id)]
        return c.url!
    }
    public static func id(from url: URL) -> String? {
        guard url.scheme == AppConfiguration.urlScheme, url.host == "task", let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = c.queryItems?.first(where: { $0.name == "id" })?.value, id.hasPrefix("task:"), id.utf8.count < 1000 else { return nil }
        return id
    }
}

public struct SharedCapture: Codable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    public init(id: String = UUID().uuidString, title: String, notes: String) { self.id = id; self.title = title; self.notes = notes }
}
public enum SharedInbox {
    public static var group: String { AppConfiguration.appGroup }
    public static func directory() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw CommandError("shared_container", "共享收集箱暂不可用，请先打开一次 Life · OS。") }
        let url = container.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static func save(_ capture: SharedCapture) throws {
        guard !capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, capture.title.utf8.count < 100_000, capture.notes.utf8.count < 100_000 else { throw CommandError("invalid_capture", "内容为空或过长。") }
        let url = try directory().appendingPathComponent(capture.id + ".json")
        try JSONEncoder().encode(capture).write(to: url, options: .atomic)
    }
}
