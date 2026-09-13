import Foundation

/// Values are shared between the app, its share extension, and their entitlements.
public enum AppConfiguration {
    public static var cloudContainer: String {
        resolved(Bundle.main.infoDictionary?["LifeOSCloudContainer"], fallback: "iCloud.com.example.LifeOS")
    }
    public static var appGroup: String {
        resolved(Bundle.main.infoDictionary?["LifeOSAppGroup"], fallback: "group.com.example.LifeOS")
    }
    public static var urlScheme: String {
        resolved(ProcessInfo.processInfo.environment["LIFEOS_URL_SCHEME"] ?? Bundle.main.infoDictionary?["LifeOSURLScheme"], fallback: "lifeos")
    }
    static func resolved(_ value: Any?, fallback: String) -> String {
        guard let value = value as? String else { return fallback }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, !result.contains("$(") else { return fallback }
        return result
    }
}
