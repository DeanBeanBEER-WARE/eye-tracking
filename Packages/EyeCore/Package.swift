// swift-tools-version: 6.0

import PackageDescription

/// The modules of the app: `CoreKit` is the shared base, `UpdateKit` holds the GitHub release updater and
/// `AppSupportKit` the AppKit helpers of the menu. Later points add the tracking, gaze and pointer modules.
let strict: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]

let package = Package(
    name: "EyeCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
        .library(name: "UpdateKit", targets: ["UpdateKit"]),
        .library(name: "AppSupportKit", targets: ["AppSupportKit"]),
    ],
    targets: [
        .target(name: "CoreKit", swiftSettings: strict),
        .target(name: "UpdateKit", dependencies: ["CoreKit"], swiftSettings: strict),
        .target(name: "AppSupportKit", dependencies: ["CoreKit"], swiftSettings: strict),
        .testTarget(
            name: "EyeCoreTests",
            dependencies: ["CoreKit", "UpdateKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
