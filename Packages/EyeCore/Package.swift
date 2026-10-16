// swift-tools-version: 6.0

import PackageDescription

/// The modules of the app: `CoreKit` is the shared base, `UpdateKit` holds the GitHub release updater,
/// `AppSupportKit` the AppKit helpers of the menu, `CMediaPipe` the C shim around the MediaPipe Tasks C API,
/// `TrackingKit` the camera and face tracking pipeline, `GazeKit` the calibration and gaze model and `PointerKit`
/// the decisions of the gaze pointer.
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
        .library(name: "GazeKit", targets: ["GazeKit"]),
        .library(name: "PointerKit", targets: ["PointerKit"]),
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
        .target(name: "GazeKit", dependencies: ["CoreKit", "TrackingKit"], swiftSettings: strict),
        .target(name: "PointerKit", dependencies: ["CoreKit", "GazeKit"], swiftSettings: strict),
        .testTarget(
            name: "EyeCoreTests",
            dependencies: ["CoreKit", "UpdateKit", "TrackingKit", "GazeKit", "PointerKit"]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
