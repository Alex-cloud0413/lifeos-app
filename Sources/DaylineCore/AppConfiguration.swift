import Foundation

/// Values are shared between the app, its share extension, and their entitlements.
public enum AppConfiguration {
    public static var cloudEnvironment: String {
        resolved(Bundle.main.infoDictionary?["LifeOSCloudEnvironment"], fallback: "Development")
    }
    /// Never attach a development store and its pending events to production.
    public static func storeFilename(cloudEnabled: Bool, environment: String) -> String {
        guard cloudEnabled else { return "Preview.store" }
        return environment == "Production" ? "Cloud-Production.store" : "Cloud.store"
    }
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
