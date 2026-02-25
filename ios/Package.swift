// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KabalCrashReporter",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "KabalCrashReporter", targets: ["KabalCrashReporter"])
    ],
    targets: [
        .target(name: "KabalCrashReporter"),
        .testTarget(name: "KabalCrashReporterTests", dependencies: ["KabalCrashReporter"])
    ]
)
