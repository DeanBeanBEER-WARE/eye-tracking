# Eye Tracking

Native macOS menu bar app that lets eye and head gaze, seen by the built-in camera, replace the movement of the external mouse. Clicks, wheel and keyboard stay physical; the built-in trackpad is never blocked. Quitting the app ends the override.

Status: `0.2.0`, face tracking with MediaPipe and a camera preview (menu "Kamera-Vorschau"). Calibration and the gaze pointer follow in the next releases.

## Requirements

- macOS 14 or later, Apple Silicon (arm64 only)
- Xcode 16.3 or later (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- The code signing identity "WhisperApp Dev Signing" in the login keychain (shared with Whisper Assistant); without it the build falls back to ad-hoc signing and macOS permissions reset after every build

## Project Layout

| Path | Content |
|---|---|
| `project.yml` | XcodeGen project definition (the `.xcodeproj` is generated and not committed) |
| `Config/` | `Version.xcconfig` (single version source), `Info.plist`, entitlements |
| `App/` | App target: AppKit menu bar UI and system integration |
| `Packages/EyeCore/` | Local Swift package with the logic modules, tested with Swift Testing |
| `assets/icon.svg` | Icon source for the menu bar icon and the app icon |
| `scripts/` | Build, icon generation and module boundary scripts |

## Modules

| Module | Content | Depends on |
|---|---|---|
| `CoreKit` | App identity, logging, settings, HTTP and process abstractions, version compare, menu model | - |
| `UpdateKit` | GitHub release check, token from the GitHub CLI, asset download, installer and swap script | `CoreKit` |
| `AppSupportKit` | AppKit helpers: alerts, notifications, process runner, detached spawn | `CoreKit` |
| `CMediaPipe` | C++ shim around the MediaPipe Tasks C API (vendored headers of v1.1.1, Apache-2.0), loads `libmediapipe.dylib` at runtime | - |
| `TrackingKit` | Camera capture, BGRA to RGB conversion, face landmarker, head pose, tracking engine | `CoreKit`, `CMediaPipe` |

## MediaPipe

There is no official MediaPipe SDK for macOS apps. The PyPI wheel `mediapipe==1.1.1` ships the Tasks C API as `libmediapipe.dylib`; `scripts/fetch_mediapipe.sh` downloads the wheel and the face landmarker model, verifies both against pinned SHA-256 checksums and puts them into the gitignored `Vendor/mediapipe/`. The app embeds the library in `Contents/Frameworks` (loaded with `dlopen`, hence the `disable-library-validation` entitlement) and the model in `Contents/Resources`.

MediaPipe contains Google's usage logging. The app hands it an empty CA bundle, so an upload could not pass TLS verification; a 25-second run of the landmarker opened no network connection.

## Development

```bash
./scripts/fetch_mediapipe.sh
xcodegen generate
swift format lint --strict --recursive App Packages
./scripts/check_boundaries.sh
swift test --package-path Packages/EyeCore
xcodebuild -project EyeTracking.xcodeproj -scheme EyeTracking -configuration Debug -derivedDataPath build/debug build
```

After changing `assets/icon.svg`, regenerate the icons from the repository root with `swift scripts/make_app_icon.swift`.

## Build and Release

```bash
./scripts/build.sh
gh release create v<version> dist/EyeTracking-<version>.dmg --title "v<version>" --notes "<summary>"
```

The script builds the Release app for arm64, signs it with the stable identity (hardened runtime) and creates `dist/EyeTracking-<version>.dmg`. The version is read from `Config/Version.xcconfig`.

## Updates

The app checks this repository for a newer release at launch and every three hours, and on demand from the menu ("Nach Updates suchen…"). A newer release is announced once by notification and stays in the menu as "Update auf Version … installieren…".

The repository is private: the app asks the [GitHub CLI](https://cli.github.com) for the token of `DeanBeanBEER-WARE` (`gh auth token --user DeanBeanBEER-WARE`, falling back to the active account), so the check works even when another `gh` account is active. The update downloads the `EyeTracking-<version>.dmg` asset through the GitHub API, verifies the bundle id `com.deanbean.eyetracking` and the signing certificate of the running app, quits, and swaps the installed bundle with a detached script that logs to `~/Library/Logs/EyeTracking/update.log` and relaunches the app.

## Permissions

The app asks for camera access when tracking starts for the first time. The camera images are processed in memory only.

## Logs and Settings

- Log: `~/Library/Logs/EyeTracking/eye_tracking.log`
- Settings: `~/Library/Application Support/EyeTracking/settings.json`
