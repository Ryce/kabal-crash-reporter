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
        .package(url: "https://github.com/kstenerud/KSCrash", from: "2.5.1")
    ],
    targets: [
        .target(
            name: "KabalCrashReporter",
            dependencies: [
                .product(name: "KSCrash", package: "KSCrash"),
                .product(name: "KSCrashInstallations", package: "KSCrash"),
                .product(name: "KSCrashSinks", package: "KSCrash")
            ]
        ),
    ]
)
