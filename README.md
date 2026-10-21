# Eye Tracking

A native macOS menu bar app that moves the mouse pointer with your gaze, using only a webcam. Your eyes and head position the pointer; clicking, scrolling, dragging and typing stay with the physical mouse and keyboard. The built-in trackpad is never taken over, so it always works as fine correction and as a way out. Quitting the app ends everything at once.

Face tracking runs fully on the Mac with Google's MediaPipe Face Landmarker. No image is stored or sent anywhere.

Current version: see [Releases](../../releases). The app is an experiment that is used daily by its author, not a polished product.

## Contents

- [What to Expect](#what-to-expect)
- [Requirements](#requirements)
- [Installation](#installation)
- [First Steps](#first-steps)
- [Menu Reference](#menu-reference)
- [How It Works](#how-it-works)
- [Privacy and Permissions](#privacy-and-permissions)
- [Hotkeys (Karabiner-Elements)](#hotkeys-karabiner-elements)
- [Project Structure](#project-structure)
- [Building from Source](#building-from-source)
- [Releases and Updates](#releases-and-updates)
- [Files on Disk](#files-on-disk)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## What to Expect

Webcam eye tracking is far less precise than dedicated infrared eye trackers. Expect an error of roughly 2 to 4 degrees of visual angle in a good setup, which is 2 to 5 cm on a monitor at arm's length. That is enough to bring the pointer close to a target, not to hit a small icon directly. Two features close the gap: snapping to clickable elements, and the trackpad for the last centimeters.

Accuracy depends mostly on the camera position. The face should look roughly towards the camera when you look at your main screen. If the camera sits far to the side, for example a MacBook next to two external monitors, the head turns 40 to 50 degrees away from it and the eye measurements degrade strongly. A camera centered above the main monitor (an iPhone as Continuity Camera works well) gives much better results. Good, even lighting on the face helps too.

The app was developed with one MacBook and two stacked ultrawide monitors, but it reads the display arrangement from macOS and works with any number and layout of displays.

## Requirements

- macOS 14 or later on Apple Silicon (arm64 only)
- A camera: built-in, USB or Continuity Camera
- An external mouse for clicks and scrolling (any USB or Bluetooth mouse; the trackpad is never taken over)
- Optional: [Karabiner-Elements](https://karabiner-elements.pqrs.org) for hotkeys

## Installation

1. Download `EyeTracking-<version>.dmg` from the latest release, open it and drag `EyeTracking.app` into `Applications`.
2. The app is signed with a self-signed certificate and not notarized by Apple, so macOS blocks the first launch. Open it once, then go to System Settings > Privacy & Security and choose "Open Anyway". Alternatively remove the quarantine flag in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/EyeTracking.app
   ```

3. Start the app. An eye icon appears in the menu bar; the app has no Dock icon.

Each disk image also contains `LICENSE.txt` and `THIRD_PARTY_NOTICES.md`.

## First Steps

1. **Choose the camera** in the menu under "Camera". A calibration belongs to the camera it was recorded with.
2. **Check the camera image** with "Camera Preview": the eye corners, lids and irises are marked, and the status line shows frame rate, inference time and head pose.
3. **Calibrate** with "Calibrate…". All displays are dimmed and dots appear one after another. Look at each dot until it disappears and keep your head still. At the end, three dots in the display centers ask you to keep looking while slowly turning and tilting your head. Esc cancels. Calibration takes about 90 seconds; afterwards a dialog shows the estimated error per display.
4. **Judge the result** with "Show Gaze Point": a red dot follows your gaze. The pointer does not move yet.
5. **Switch on "Gaze Control"**. The first time, macOS asks for the Accessibility permission (see [Privacy and Permissions](#privacy-and-permissions)); gaze control starts as soon as it is granted.

### Using an iPhone as Camera

There is no pairing step in the app. With Continuity Camera, macOS itself offers a nearby iPhone as a regular camera, and it appears in the "Camera" menu as "<name of the iPhone> Camera". Requirements:

- the iPhone is close to the Mac and signed in with the same Apple ID
- Wi-Fi and Bluetooth are on on both devices
- Continuity Camera is enabled on the iPhone (Settings > General > AirPlay & Continuity)
- the iPhone is locked and mounted steadily, ideally in landscape, centered above your main screen

The connection is made when the app opens the camera. Choosing a camera in the menu therefore opens the camera preview: its title names the active camera, and it shows "Waiting for …" until the first image arrives, which takes a few seconds for an iPhone. If no image arrives within 10 seconds, the app shows these requirements. Calibrate again after switching, because a calibration belongs to its camera.

Calibrate again whenever you change the camera, its position or your display arrangement. The app notices display and camera changes and switches gaze control off until a matching calibration exists.

## Menu Reference

| Entry | Function |
|---|---|
| Version line | Shows the installed version. |
| Gaze Control | Moves the pointer with your gaze and takes over the external mouse while your face is visible. Can always be switched off. Its state is restored at the next launch. |
| Snap to Controls | After the gaze lands, moves the pointer onto the nearest clickable element (on by default). |
| Calibrate… | Starts a calibration on all displays. |
| Show Gaze Point | Shows the live gaze estimate as a red dot above all windows. |
| Camera Preview | Opens a window with the mirrored camera image and the tracked landmarks. |
| Camera | Chooses the camera. |
| Install Update to Version … | Appears when a newer release was found. |
| Check for Updates… | Asks GitHub for the latest release. |
| Show Log… | Opens the log file. |
| Quit | Quits the app and gives the mouse back immediately. |

## How It Works

The pipeline runs from camera frame to pointer event in the following steps.

### 1. Face Tracking

The camera delivers 1280x720 frames at 30 frames per second (AVFoundation, BGRA). Each frame is converted to RGB with vImage and handed to the MediaPipe Face Landmarker in video mode. It returns 478 face landmarks including both irises, 52 blendshape scores (for example `eyeLookOutLeft` or `eyeBlinkRight`) and a facial transformation matrix. Head yaw, pitch, roll and position are derived from that matrix.

MediaPipe has no official SDK for macOS apps. The app therefore uses the MediaPipe Tasks C API, which ships as `libmediapipe.dylib` inside the official PyPI wheel. A small C++ shim (`CMediaPipe`) loads the library at runtime with `dlopen` and exposes a plain C interface to Swift. MediaPipe contains Google's usage logging; the shim passes it an empty certificate bundle, so any upload attempt fails TLS verification and no data leaves the Mac.

### 2. Gaze Features

For every frame, 14 values are computed:

- the iris offset of each eye along and across the line through its two corners, normalized by the eye width (the corners do not move when you look up or down, unlike the lids)
- horizontal and vertical gaze from the eye-look blendshapes
- head yaw, pitch and roll in degrees, and head position in centimeters
- the lid opening of each eye

Both eyes stay separate, so the model can rely on the eye that faces the camera. A frame counts as a blink only when both eyes are closed, because the eye turned away from the camera often looks closed.

### 3. Calibration and Gaze Model

The calibration shows a 5x3 grid on wide displays (aspect ratio 1.9 or more) and a 3x3 grid on the others: the built-in display first, then the other displays from bottom to top, each grid in snake order. Every grid dot waits 0.7 seconds for the eyes to settle, then records for 1 second. Then one dot per display center records for 3 seconds while the head moves. Blinks are skipped, and every dot needs a minimum number of samples or is skipped after a timeout.

The gaze model is ridge regression in two stages:

1. The features are standardized and extended with squares and pairwise products of the eye, blendshape, yaw and pitch values.
2. A global model predicts a point in the combined display space; the display nearest to it is chosen.
3. A model per display refines the position on that display (quadratic with 9 or more dots, linear with fewer).

The regularization strength is chosen by leave-one-dot-out cross-validation over seven values. The median cross-validated error per display is the accuracy shown at the end of the calibration. Fitting takes well under a second. The model, the calibration samples and, for offline analysis, the raw eye landmarks of every sample are saved to `calibration.json`. A model is only used while the display arrangement, the camera and the feature version match.

### 4. Smoothing

The predicted point is smoothed with a One Euro filter (strong smoothing at rest, little lag during fast movements). Gaze speed in degrees per second is derived from the smoothed point, the physical display size and an assumed viewing distance of 65 cm.

### 5. Pointer Control

The pointer follows saccades, not every flicker of the estimate:

- While your gaze rests, the pointer rests. When the gaze moves more than 2 degrees away from where it rested, the pointer follows the smoothed gaze until the gaze settles again (below 8 degrees per second for 0.12 seconds). The dead zone is measured in gaze space, so a pointer you corrected with the trackpad is not pulled back to the slightly wrong estimate.
- While a mouse button is held, and for 0.35 seconds after it is released, the pointer stays still, so clicks and double clicks land where you aimed.
- Any movement or click of the trackpad (or any other device that is not taken over) pauses gaze for 1.2 seconds.
- Without a visible face for 1 second, the mouse is given back and works normally. It is taken again once the face has been visible for 0.4 seconds.

**Taking over the external mouse.** While gaze control is active and a face is visible, the app opens every external mouse interface with exclusive access (IOKit HID seize). From then on its motion no longer reaches macOS. The built-in trackpad, other trackpads, keyboards (including the keyboard interface of gaming mice that carries macro keys) and Karabiner's virtual devices are never taken. The buttons, wheel and tilt of the seized mouse are read and posted again as regular macOS events, including click counts for double clicks and the current modifier keys. Its motion is only used for dragging while a button is held. Exclusive access ends when gaze control stops, when the face is lost, when the app quits and, through the kernel, also when the app crashes.

**Telling devices apart.** Every event the app posts carries a private tag. A listen-only event tap watches all pointer events; any event without the tag comes from a device that is not taken over, which is what pauses gaze.

**Snapping.** When the gaze has landed, a background task hit-tests 17 points within 2.5 degrees around it with the Accessibility API. It walks up from each hit to the nearest clickable element: buttons, links, checkboxes, pop-up buttons, menu items, text and search fields, tabs, or elements that offer the press action. The pointer moves to the center of the nearest element, unless two elements are about equally near, the element is very large, or anything changed in the meantime.

## Privacy and Permissions

- **Camera**: requested when tracking starts for the first time. Frames are processed in memory and dropped; nothing is recorded. The camera only runs while the preview, a calibration, the gaze point or gaze control needs it, and the system camera indicator shows when it is on.
- **Accessibility**: needed by gaze control to post pointer events and to read clickable elements for snapping. The permission is read live, so gaze control starts as soon as it is granted.
- **Input Monitoring**: only requested if macOS refuses to hand over the mouse. Taking over a pure mouse interface normally needs no permission.
- **Network**: the only connections are the update check to `api.github.com` and the download of a release you chose to install. MediaPipe's usage logging is blocked as described above.
- **Notifications**: optional, used once per new release.

## Hotkeys (Karabiner-Elements)

The app handles the URL scheme `eyetracking://` with these commands:

| URL | Action |
|---|---|
| `eyetracking://toggle` | Switch gaze control on or off |
| `eyetracking://pause-start` | Pause gaze control; the mouse works normally |
| `eyetracking://pause-end` | End the pause |
| `eyetracking://recalibrate` | Start a calibration |

Any tool can send them with `open -g 'eyetracking://toggle'`. The file `integrations/karabiner/eye_tracking.json` contains ready-made rules for Karabiner-Elements. Copy it to `~/.config/karabiner/assets/complex_modifications/`, then enable the rules you want under Complex Modifications > Add predefined rule.

| Keys | Action |
|---|---|
| Ctrl+Option+Command+G | Gaze control on/off |
| Caps Lock held (a short tap still toggles Caps Lock) | Pause while held |
| Ctrl+Option+Command+P held | Pause while held, without touching Caps Lock |
| Ctrl+Option+Command+K | Calibrate |

## Project Structure

| Path | Content |
|---|---|
| `project.yml` | XcodeGen project definition; the `.xcodeproj` is generated and not committed |
| `Config/` | `Version.xcconfig` (the only version source), `Info.plist`, entitlements |
| `App/` | App target: AppKit user interface and system integration |
| `Packages/EyeCore/` | Local Swift package with the logic modules and their tests |
| `scripts/` | Build, MediaPipe download, module boundary check, icon generation |
| `integrations/karabiner/` | Karabiner-Elements rules for the hotkeys |
| `assets/icon.svg` | Source of the app and menu bar icon |

### Package Modules (`Packages/EyeCore`)

| Module | Content | Depends on |
|---|---|---|
| `CoreKit` | App identity, logging, settings, HTTP and process abstractions, version comparison, menu model, hotkey commands | - |
| `UpdateKit` | GitHub release check, disk image download, staging, signature check and swap script | `CoreKit` |
| `AppSupportKit` | Alerts, notifications, process runner, detached process launch | `CoreKit` |
| `CMediaPipe` | C++ shim around the MediaPipe Tasks C API; vendored headers of MediaPipe v1.1.1 | - |
| `TrackingKit` | Camera capture, color conversion, face landmarker, head pose, tracking engine, gaze features | `CoreKit`, `CMediaPipe` |
| `GazeKit` | Display layout, calibration plan, ridge regression, gaze model with cross-validation, One Euro filter, gaze estimator, calibration store | `CoreKit`, `TrackingKit` |
| `PointerKit` | Pointer policy, face engagement, snap target selection, HID input decoding, scroll mapping, click counting | `CoreKit`, `GazeKit` |

`scripts/check_boundaries.sh` fails the build when a module imports a module it may not depend on. All logic that can be tested without hardware lives in the package and is covered by Swift Testing tests.

### App Target (`App/`)

| Folder | Content |
|---|---|
| `Menu/` | Status item, menu rendering from `MenuModel`, menu actions, menu titles |
| `Tracking/` | `TrackingController` (starts the camera while any part of the app needs it and forwards every result), camera preview window |
| `Gaze/` | `GazeService` (holds the model, turns tracking results into gaze estimates), `CalibrationController`, `GazeDotController` |
| `Overlay/` | Click-through full-screen windows on every display for the calibration and the gaze dot |
| `Pointer/` | `PointerController`, `MouseSeizer` (IOKit HID), `EventPoster` (Core Graphics events), `ManualInputMonitor` (event tap), `ElementSnapper` (Accessibility), permissions |
| `System/` | Updater, update installer with signature check, display layout reader |
| `Resources/` | String catalog (English), app icon |

Data flow: `CameraCapture` -> `TrackingEngine` (MediaPipe) -> `TrackingController` -> `FeatureExtractor` -> `GazeEstimator` -> `GazeService` -> `PointerController` / `GazeDotController`; the `CalibrationController` taps the same stream to record samples.

## Building from Source

Requirements: Xcode 16.3 or later (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and an internet connection for the first MediaPipe download.

```bash
./scripts/fetch_mediapipe.sh
xcodegen generate
open EyeTracking.xcodeproj
```

`fetch_mediapipe.sh` downloads the pinned MediaPipe 1.1.1 wheel and the face landmarker model, verifies both against SHA-256 checksums and places the library, the model and MediaPipe's license and notice files in the gitignored `Vendor/mediapipe/`.

Verification, as run before every commit:

```bash
swift format lint --strict --recursive App Packages
./scripts/check_boundaries.sh
swift test --package-path Packages/EyeCore
xcodebuild -project EyeTracking.xcodeproj -scheme EyeTracking -configuration Debug -derivedDataPath build/debug build
```

The project uses Swift 6 strict concurrency and treats warnings as errors.

### Signing

macOS ties camera and Accessibility permissions to the code signature, so a stable signing identity matters: with ad-hoc signing every rebuild loses the granted permissions. `scripts/build.sh` signs with the identity named in `SIGN_IDENTITY` (default: `WhisperApp Dev Signing`, the author's self-signed certificate) and falls back to ad-hoc signing if it does not exist. To use your own, create a self-signed code signing certificate in Keychain Access (Certificate Assistant > Create a Certificate, type "Code Signing") and build with:

```bash
SIGN_IDENTITY="My Code Signing" ./scripts/build.sh
```

The result is `dist/EyeTracking.app` and `dist/EyeTracking-<version>.dmg`.

### Forking

To publish your own builds, change `AppInfo.repositorySlug` (and `AppInfo.githubAccount` for a private fork) in `Packages/EyeCore/Sources/CoreKit/AppInfo.swift`, the bundle identifier in `project.yml` and `AppInfo.bundleIdentifier`, and use your own signing identity.

## Releases and Updates

A release is a GitHub release with the asset `EyeTracking-<version>.dmg`:

```bash
./scripts/build.sh
gh release create v<version> dist/EyeTracking-<version>.dmg --title "v<version>" --notes "<summary>"
```

The app checks for a newer release at launch and every three hours, and on demand with "Check for Updates…". A new release is announced once per version and stays in the menu until installed. The check is anonymous. Only if the repository is not public (a private fork) does it retry with a token from the GitHub CLI (`gh auth token`), and only then does the download use it too.

Installing an update downloads the disk image, mounts it, copies the app to a staging folder and checks two things: the bundle identifier, and that the new app is signed with the same certificate as the running one. The app then quits, and a detached script waits for it to exit, swaps the bundles (keeping the old one until the copy succeeded) and relaunches the app. The script logs to `~/Library/Logs/EyeTracking/update.log`.

## Files on Disk

| Path | Content |
|---|---|
| `~/Library/Application Support/EyeTracking/settings.json` | Camera, gaze control and snapping state, last announced release |
| `~/Library/Application Support/EyeTracking/calibration.json` | Gaze model, calibration samples and raw eye landmarks |
| `~/Library/Application Support/EyeTracking/mediapipe-no-upload.pem` | Empty certificate bundle that blocks MediaPipe's usage logging |
| `~/Library/Logs/EyeTracking/eye_tracking.log` | App log (rotating) |
| `~/Library/Logs/EyeTracking/update.log` | Log of the update script |

Deleting the folders resets the app. The log never contains images or tokens.

## Troubleshooting

| Problem | What to do |
|---|---|
| The pointer is far off | Check "Show Gaze Point". Calibrate again in good light, keep your head still at the grid dots. If the camera is far to the side of your main screen, move it or use a centered camera. |
| The pointer freezes in some areas | Check "Camera Preview" while looking there: if the face or eyes are lost, the camera angle is too steep. |
| Gaze control cannot be switched on | It needs a calibration for the current displays and camera, and the Accessibility permission. |
| The mouse does not move at all | Expected while gaze control is active and your face is visible. Hold the pause hotkey, look away from the camera, use the trackpad, or switch gaze control off. |
| The log says a mouse "could not be taken over" | Another tool holds exclusive access to it (for example Karabiner-Elements configured to modify that mouse), or macOS requires Input Monitoring. |
| Scrolling goes the wrong way | The app follows the "Natural scrolling" setting of macOS; report your mouse model if it still does not match. |
| The update fails with a signature error | Your installed build and the release are signed with different certificates; install the release manually once. |

## License

Eye Tracking is released under the MIT License, see `LICENSE`. It redistributes the MediaPipe Tasks C API library and the Face Landmarker model, both under the Apache License 2.0. Details and attributions are in `THIRD_PARTY_NOTICES.md`; every app bundle contains MediaPipe's license and notice files.
