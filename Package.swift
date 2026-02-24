// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KabalCrashReporter",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "KabalCrashReporter",
            targets: ["KabalCrashReporter"]
        ),
    ],
    targets: [
        .target(
            name: "KabalCrashReporter",
            dependencies: []
        ),
    ]
)
