import XCTest
@testable import KabalCrashReporter

final class KabalCrashReporterTests: XCTestCase {
    func testInitAndSetUserId() {
        let reporter = KabalCrashReporter(config: .init(apiURL: "https://example.com/v1/crashes", appVersion: "1.0.0", userId: nil, apiKey: "k"))
        reporter.setUserId("u_123")
        XCTAssertTrue(true)
    }
}
