// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KabalCrashReporter",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "KabalCrashReporter", targets: ["KabalCrashReporter"])
    ],
    dependencies: [
        .package(url: "https://github.com/kstenerud/KSCrash.git", exact: "2.5.1")
    ],
    targets: [
        .target(
            name: "KabalCrashReporter",
            dependencies: [
                .product(name: "Installations", package: "KSCrash")
            ]
        ),
        .testTarget(name: "KabalCrashReporterTests", dependencies: ["KabalCrashReporter"])
    ]
)
