# Eye Tracking

Native macOS menu bar app that lets eye and head gaze, seen by the built-in camera, replace the movement of the external mouse. Clicks, wheel and keyboard stay physical; the built-in trackpad is never blocked. Quitting the app ends the override.

Status: `0.4.0`, gaze control of the pointer (menu "Blicksteuerung"), calibration over all displays (menu "Kalibrieren …"), a live gaze dot to judge it (menu "Blickpunkt anzeigen"), camera preview and Karabiner hotkeys. Snapping to UI elements, drift handling and a settings window follow.

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
| `TrackingKit` | Camera capture, BGRA to RGB conversion, face landmarker, head pose, tracking engine, gaze features | `CoreKit`, `CMediaPipe` |
| `GazeKit` | Display layout, calibration plan, ridge regression gaze model with cross-validation, One Euro smoothing, gaze estimator, calibration store | `CoreKit`, `TrackingKit` |
| `PointerKit` | Pointer policy (saccades, dead zone, button freeze, trackpad pause), face engagement hysteresis, HID input decoding, scroll mapping, click counting | `CoreKit`, `GazeKit` |

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

## Calibration

"Kalibrieren …" dims all displays and shows targets one after another: a 3x3 grid on the ultrawides, 3x2 on the built-in display (built-in first, then bottom to top), then one target per display center while the head moves slightly. Esc cancels. The model maps iris offsets, eye blendshapes and head pose to screen points: a global ridge regression picks the display, a model per display refines the position; the penalty is chosen by leave-one-target-out cross-validation, whose median error per display is reported at the end. The model is saved to `~/Library/Application Support/EyeTracking/calibration.json` and only used while the display arrangement matches the one it was calibrated on.

## Gaze Control

"Blicksteuerung" moves the cursor with the gaze; clicks, wheel and keyboard stay physical.

- The cursor rests while the gaze rests. It follows only when the gaze leaves its resting spot by more than 2 degrees (a saccade) and stops again when the gaze settles. The dead zone is measured in gaze space, so a cursor corrected with the trackpad is not pulled back.
- While the face is visible, the app takes exclusive access to the external mouse (IOKit HID seize of its mouse interface; the built-in trackpad, other trackpads and Karabiner's virtual devices are never touched). Its buttons, wheel and tilt are re-injected as events; its motion only drags while a button is held, and the cursor stays frozen during that time and briefly after a release, so double clicks land on one spot.
- Moving or clicking the trackpad pauses gaze for 1.2 seconds: it is the fine correction and the way out.
- Without a face for one second the mouse is given back and works normally; it is taken again after the face is visible for 0.4 seconds.
- Quitting the app (or a crash) ends the exclusive access at once. Gaze control is switched on again at launch if it was on, and it stops when the display arrangement no longer matches the calibration.

## Hotkeys

The app handles the URL scheme `eyetracking://` with the commands `toggle`, `pause-start`, `pause-end` and `recalibrate`. `integrations/karabiner/eye_tracking.json` contains Karabiner-Elements rules (copy it to `~/.config/karabiner/assets/complex_modifications/` and enable the rules in Karabiner's settings):

| Keys | Action |
|---|---|
| Ctrl+Option+Command+G | Gaze control on/off |
| Caps Lock held (tap = Caps Lock) | Pause gaze control while held; the mouse works normally |
| Ctrl+Option+Command+P held | Same pause, without Caps Lock |
| Ctrl+Option+Command+K | Calibrate |

## Permissions

- Camera: asked when tracking starts for the first time. The camera images are processed in memory only.
- Accessibility: needed by gaze control to move the cursor and re-inject the mouse buttons, wheel and drags. Gaze control starts automatically once it is granted.
- Input Monitoring: only asked for if macOS refuses to hand over the mouse.

## Logs and Settings

- Log: `~/Library/Logs/EyeTracking/eye_tracking.log`
- Settings: `~/Library/Application Support/EyeTracking/settings.json`
- Calibration: `~/Library/Application Support/EyeTracking/calibration.json`
