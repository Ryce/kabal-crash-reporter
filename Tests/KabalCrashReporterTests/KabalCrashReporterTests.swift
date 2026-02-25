import XCTest
@testable import KabalCrashReporter

final class KabalCrashReporterTests: XCTestCase {
    func testConfigure() {
        let sdk = KabalCrashReporterSDK.shared
        sdk.configure(endpoint: URL(string: "https://example.com")!, apiKey: "k", appVersion: "1.0", buildNumber: "1")
        XCTAssertTrue(true)
    }
}
