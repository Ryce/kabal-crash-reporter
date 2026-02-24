//
//  KabalCrashReporter.swift
//  KabalCrashReporter
//
//  Lightweight crash reporter that wraps KSCrash and sends to custom API
//

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
        
        public init(apiURL: String, appVersion: String, userId: String? = nil) {
            self.apiURL = apiURL
            self.appVersion = appVersion
            self.userId = userId
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
    
    private var config: Config
    
    public static let shared = KabalCrashReporter(config: Config(apiURL: "", appVersion: ""))
    
    public init(config: Config) {
        self.config = config
    }
    
    /// Initialize and start crash reporting
    public func start() {
        // Kabal calls `KabalCrashReporter(config: ...).start()` but reports through `.shared`.
        // Mirror the runtime config into the shared singleton for those call sites.
        KabalCrashReporter.shared.config = config

        do {
            // Configure KSCrash v2
            let crashConfig = KSCrashConfiguration()
            crashConfig.monitors = .productionSafe
            
            // Configure report store
            let storeConfig = CrashReportStoreConfiguration()
            storeConfig.maxReportCount = 10
            crashConfig.reportStoreConfiguration = storeConfig
            
            // Install KSCrash with config
            try KSCrash.shared.install(with: crashConfig)
            
            // Set up custom sink for our API
            setupCustomSink()
            
            // KSCrash handles uncaught exceptions as part of its installed monitors.
            
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
        
        // Create HTTP sink for custom URL
        let sink = CrashReportSinkStandard(url: url)
        
        // Set as sink for report store
        KSCrash.shared.reportStore?.sink = sink
        
        // Attempt to upload any cached reports on startup.
        KSCrash.shared.reportStore?.sendAllReports(completion: nil)
    }
    
    /// Get device info for crash context
    public func getDeviceInfo() -> DeviceInfo {
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = getDeviceModel()
        let appBundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let isJailbroken = checkIfJailbroken()
        
        var memoryUsage: UInt64?
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
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
    
    /// Manually report a non-fatal error
    public func reportError(name: String, message: String?, stackTrace: String?) {
        reportError(name: name, message: message, stackTrace: stackTrace, context: nil)
    }
    
    /// Report a network/API error with full context
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
    
    /// Report feedback from user
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
    
    /// Error types for feedback
    public enum FeedbackType: String {
        case onboarding = "onboarding"
        case settings = "settings"
        case bugReport = "bug_report"
        case featureRequest = "feature_request"
        case general = "general"
    }
    
    // MARK: - Private
    
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
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: report)
        } catch {
            print("[KabalCrashReporter] Failed to encode crash report: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
        ]
        return deviceMap[identifier] ?? identifier
    }
    
    private func checkIfJailbroken() -> Bool {
        let fileManager = FileManager.default
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        
        for path in jailbreakPaths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }
        
        return false
    }
    
    private func encodeToJSON<T: Encodable>(_ object: T) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(object),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}

// MARK: - Error Extension for Stack Trace
extension Error {
    var stackTrace: String {
        return Thread.callStackSymbols.joined(separator: "\n")
    }
}
