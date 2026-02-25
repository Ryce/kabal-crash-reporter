import Foundation
import UIKit
import KSCrashRecording
import KSCrashInstallations
import KSCrashSinks

public final class KabalCrashReporter {
    public struct Config {
        public let apiURL: String
        public let appVersion: String
        public let userId: String?
        public let apiKey: String?

        public init(apiURL: String, appVersion: String, userId: String? = nil, apiKey: String? = nil) {
            self.apiURL = apiURL
            self.appVersion = appVersion
            self.userId = userId
            self.apiKey = apiKey
        }
    }

    public struct DeviceInfo: Codable {
        public let osVersion: String
        public let deviceModel: String
        public let appBundleId: String
        public let isJailbroken: Bool
        public let memoryUsage: UInt64?

        public init(osVersion: String, deviceModel: String, appBundleId: String, isJailbroken: Bool, memoryUsage: UInt64?) {
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.appBundleId = appBundleId
            self.isJailbroken = isJailbroken
            self.memoryUsage = memoryUsage
        }
    }

    public enum FeedbackType: String {
        case onboarding = "onboarding"
        case settings = "settings"
        case bugReport = "bug_report"
        case featureRequest = "feature_request"
        case general = "general"
    }

    private var config: Config
    public static let shared = KabalCrashReporter(config: Config(apiURL: "", appVersion: ""))

    public init(config: Config) {
        self.config = config
    }

    public func setUserId(_ userId: String?) {
        config = Config(
            apiURL: config.apiURL,
            appVersion: config.appVersion,
            userId: userId,
            apiKey: config.apiKey
        )
    }

    public func start() {
        KabalCrashReporter.shared.config = config
        setupUnhandledExceptionHandler()

        do {
            let crashConfig = KSCrashConfiguration()
            crashConfig.monitors = .productionSafe

            let storeConfig = CrashReportStoreConfiguration()
            storeConfig.maxReportCount = 10
            crashConfig.reportStoreConfiguration = storeConfig

            try KSCrash.shared.install(with: crashConfig)
            setupCustomSink()
            print("[KabalCrashReporter] Started - sending to \(config.apiURL)")
        } catch {
            print("[KabalCrashReporter] Failed to install: \(error)")
        }
    }

    private func setupCustomSink() {
        guard let url = URL(string: config.apiURL), !config.apiURL.isEmpty else {
            print("[KabalCrashReporter] No API URL configured, crash reports will only be stored locally")
            return
        }

        let sink = CrashReportSinkStandard(url: url)
        KSCrash.shared.reportStore?.sink = sink
        KSCrash.shared.reportStore?.sendAllReports(completion: nil)
    }

    public func getDeviceInfo() -> DeviceInfo {
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = getDeviceModel()
        let appBundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let isJailbroken = checkIfJailbroken()

        var memoryUsage: UInt64?
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryUsage = UInt64(taskInfo.phys_footprint)
        }

        return DeviceInfo(
            osVersion: osVersion,
            deviceModel: deviceModel,
            appBundleId: appBundleId,
            isJailbroken: isJailbroken,
            memoryUsage: memoryUsage
        )
    }

    public func reportError(name: String, message: String?, stackTrace: String?) {
        reportError(name: name, message: message, stackTrace: stackTrace, context: nil)
    }

    public func reportNetworkError(url: String, statusCode: Int?, error: Error?) {
        let context: [String: Any] = [
            "type": "network_error",
            "url": url,
            "status_code": statusCode ?? 0,
            "error_description": error?.localizedDescription ?? ""
        ]

        reportError(
            name: "NetworkError",
            message: error?.localizedDescription ?? "HTTP \(statusCode ?? 0)",
            stackTrace: error.map { $0.stackTrace } ?? "",
            context: context
        )
    }

    public func reportFeedback(type: FeedbackType, message: String, context: [String: Any]? = nil) {
        var feedbackContext = context ?? [:]
        feedbackContext["feedback_type"] = type.rawValue
        feedbackContext["message"] = message

        let report: [String: Any] = [
            "platform": "ios",
            "app_version": config.appVersion,
            "error_name": "FEEDBACK",
            "message": message,
            "stack_trace": "",
            "user_id": config.userId ?? "",
            "device_info": encodeToJSON(getDeviceInfo()),
            "context": feedbackContext
        ]

        sendCrashReport(report)
    }

    private func reportError(name: String, message: String?, stackTrace: String?, context: [String: Any]?) {
        var ctx = context ?? [:]
        ctx["timestamp"] = Int(Date().timeIntervalSince1970)

        let crashReport: [String: Any] = [
            "platform": "ios",
            "app_version": config.appVersion,
            "error_name": name,
            "message": message ?? "",
            "stack_trace": stackTrace ?? "",
            "user_id": config.userId ?? "",
            "device_info": encodeToJSON(getDeviceInfo()),
            "context": ctx
        ]

        sendCrashReport(crashReport)
    }

    private func setupUnhandledExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let stackTrace = exception.callStackSymbols.joined(separator: "\n")
            let crashReport: [String: Any] = [
                "platform": "ios",
                "app_version": KabalCrashReporter.shared.config.appVersion,
                "error_name": "Unhandled Exception",
                "message": exception.reason ?? "No message",
                "stack_trace": stackTrace,
                "user_id": KabalCrashReporter.shared.config.userId ?? "",
                "device_info": KabalCrashReporter.shared.encodeToJSON(KabalCrashReporter.shared.getDeviceInfo()),
                "context": [
                    "url": "",
                    "user_agent": "Kabal-iOS",
                    "timestamp": Int(Date().timeIntervalSince1970)
                ]
            ]

            KabalCrashReporter.shared.sendCrashReport(crashReport)
        }
    }

    private func sendCrashReport(_ report: [String: Any]) {
        guard let url = URL(string: config.apiURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = config.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: report)
        } catch {
            print("[KabalCrashReporter] Failed to encode crash report: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[KabalCrashReporter] Failed to send crash: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("[KabalCrashReporter] Crash sent, status: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapToDevice(identifier: identifier)
    }

    private func mapToDevice(identifier: String) -> String {
        let deviceMap: [String: String] = [
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max"
        ]
        return deviceMap[identifier] ?? identifier
    }

    private func checkIfJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
        #endif
    }

    fileprivate func encodeToJSON<T: Encodable>(_ value: T) -> String {
        do {
            let data = try JSONEncoder().encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
}

private extension Error {
    var stackTrace: String {
        Thread.callStackSymbols.joined(separator: "\n")
    }
}
