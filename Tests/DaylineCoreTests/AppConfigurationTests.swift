import XCTest
@testable import DaylineCore

final class AppConfigurationTests: XCTestCase {
    func testUnexpandedSettingsDoNotBecomeContainerIdentifiers() {
        XCTAssertEqual(AppConfiguration.resolved("$(LIFEOS_CLOUD_CONTAINER)", fallback: "fallback"), "fallback")
        XCTAssertEqual(AppConfiguration.resolved("  ", fallback: "fallback"), "fallback")
        XCTAssertEqual(AppConfiguration.resolved(nil, fallback: "fallback"), "fallback")
        XCTAssertEqual(AppConfiguration.resolved(" iCloud.com.example.Custom ", fallback: "fallback"), "iCloud.com.example.Custom")
    }
    #if os(macOS)
    func testCLIUsesTheForksBundleIdentifier() {
        let paths = LocalTransport.socketCandidates(home: "/Users/test", bundleIdentifier: "com.test.Custom")
        XCTAssertEqual(paths, [
            "/Users/test/Library/Containers/com.test.Custom/Data/Library/Application Support/DL/cli.sock",
            "/Users/test/Library/Application Support/LifeOS/cli.sock"
        ])
        XCTAssertEqual(TaskLink.url("task:example").scheme, "lifeos")
    }
    #endif
}
