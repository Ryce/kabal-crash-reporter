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
    dependencies: [
        .package(url: "https://github.com/kstenerud/KSCrash", from: "1.15.0")
    ],
    targets: [
        .target(
            name: "KabalCrashReporter",
            dependencies: ["KSCrash"]
        ),
    ]
)
