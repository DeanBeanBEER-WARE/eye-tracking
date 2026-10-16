// swift-tools-version: 6.0

import PackageDescription

/// The modules of the app: `CoreKit` is the shared base, `UpdateKit` holds the GitHub release updater,
/// `AppSupportKit` the AppKit helpers of the menu, `CMediaPipe` the C shim around the MediaPipe Tasks C API and
/// `TrackingKit` the camera and face tracking pipeline. Later points add the gaze and pointer modules.
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
        .library(name: "TrackingKit", targets: ["TrackingKit"]),
    ],
    targets: [
        .target(name: "CoreKit", swiftSettings: strict),
        .target(name: "UpdateKit", dependencies: ["CoreKit"], swiftSettings: strict),
        .target(name: "AppSupportKit", dependencies: ["CoreKit"], swiftSettings: strict),
        .target(
            name: "CMediaPipe",
            exclude: ["vendor/LICENSE"],
            cxxSettings: [.headerSearchPath("vendor")]
        ),
        .target(name: "TrackingKit", dependencies: ["CoreKit", "CMediaPipe"], swiftSettings: strict),
        .testTarget(
            name: "EyeCoreTests",
            dependencies: ["CoreKit", "UpdateKit", "TrackingKit"]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
