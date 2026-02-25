import Foundation

public struct CrashReport: Codable {
    public let appId: String
    public let platform: String
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String
    public let userId: String?
    public let title: String?
    public let reason: String?
    public let stackTrace: String?
    public let payload: [String: String]?
}

public final class KabalCrashReporterSDK {
    public static let shared = KabalCrashReporterSDK()

    private var endpoint: URL?
    private var apiKey: String?
    private var appVersion: String = "unknown"
    private var buildNumber: String = "unknown"

    private init() {}

    public func configure(endpoint: URL, apiKey: String, appVersion: String, buildNumber: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    public func reportNonFatal(appId: String, title: String, reason: String?, userId: String? = nil, extra: [String: String]? = nil) {
        let report = CrashReport(
            appId: appId,
            platform: "ios",
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: "iPhone",
            userId: userId,
            title: title,
            reason: reason,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n"),
            payload: extra
        )
        send(report)
    }

    public func reportFeedback(appId: String, message: String, userId: String? = nil, extra: [String: String]? = nil) {
        guard let endpoint, let apiKey else { return }
        let url = endpoint.appendingPathComponent("v1/feedback")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        let payload: [String: Any?] = [
            "appId": appId,
            "userId": userId,
            "message": message,
            "payload": extra
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])
        URLSession.shared.dataTask(with: req).resume()
    }

    private func send(_ report: CrashReport) {
        guard let endpoint, let apiKey else { return }
        let url = endpoint.appendingPathComponent("v1/crashes")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = try? JSONEncoder().encode(report)
        URLSession.shared.dataTask(with: req).resume()
    }
}
