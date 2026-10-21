import Foundation
import Testing

@testable import CoreKit

@Suite("Core")
struct CoreTests {
    @Test("The menu shows version, gaze control, calibration, gaze dot, preview, update check, log and quit")
    func menuDefault() {
        let nodes = MenuModel.build(state: MenuState(version: "0.1.0"))
        #expect(
            nodes == [
                .item(MenuItem(.version("0.1.0"))),
                .separator,
                .item(MenuItem(.gazeControl)),
                .item(MenuItem(.snapping, command: .toggleSnapping)),
                .item(MenuItem(.calibrate, command: .calibrate)),
                .item(MenuItem(.gazeDot)),
                .separator,
                .item(MenuItem(.preview, command: .togglePreview)),
                .separator,
                .item(MenuItem(.checkForUpdates, command: .checkForUpdates)),
                .separator,
                .item(MenuItem(.showLog, command: .showLog)),
                .item(MenuItem(.quit, command: .quit, keyEquivalent: "q")),
            ])
    }

    @Test("Gaze control and the gaze dot need a calibration; a running calibration disables them")
    func menuCalibration() {
        let ready = MenuModel.build(state: MenuState(version: "0.3.0", hasCalibration: true, isGazeDotVisible: true))
        #expect(ready[2] == .item(MenuItem(.gazeControl, command: .toggleGazeControl)))
        #expect(ready[5] == .item(MenuItem(.gazeDot, command: .toggleGazeDot, isChecked: true)))
        let running = MenuModel.build(state: MenuState(version: "0.3.0", hasCalibration: true, isCalibrating: true))
        #expect(running[2] == .item(MenuItem(.gazeControl)))
        #expect(running[4] == .item(MenuItem(.calibrating)))
        #expect(running[5] == .item(MenuItem(.gazeDot)))
        let on = MenuModel.build(state: MenuState(version: "0.4.0", isGazeControlOn: true, isSnappingOn: true))
        #expect(on[2] == .item(MenuItem(.gazeControl, command: .toggleGazeControl, isChecked: true)))
        #expect(on[3] == .item(MenuItem(.snapping, command: .toggleSnapping, isChecked: true)))
    }

    @Test("A found update adds the install entry; a running check disables the check entry")
    func menuUpdate() {
        let nodes = MenuModel.build(
            state: MenuState(version: "0.1.0", availableUpdate: "0.1.1", isCheckingForUpdates: true))
        #expect(nodes[9] == .item(MenuItem(.installUpdate("0.1.1"), command: .installUpdate)))
        #expect(nodes[10] == .item(MenuItem(.checkingForUpdates)))
    }

    @Test("Cameras form a submenu with the selected one checked; the open preview is checked")
    func menuCameras() {
        let state = MenuState(
            version: "0.2.0", isPreviewVisible: true,
            cameras: [
                CameraChoice(id: "a", name: "FaceTime", isSelected: true),
                CameraChoice(id: "b", name: "iPhone", isSelected: false),
            ])
        let nodes = MenuModel.build(state: state)
        #expect(nodes[7] == .item(MenuItem(.preview, command: .togglePreview, isChecked: true)))
        #expect(
            nodes[8]
                == .submenu(
                    .camera,
                    [
                        .item(MenuItem(.cameraDevice("FaceTime"), command: .selectCamera("a"), isChecked: true)),
                        .item(MenuItem(.cameraDevice("iPhone"), command: .selectCamera("b"))),
                    ]))
    }

    @Test("Hotkey URLs map to commands and back")
    func hotkeys() throws {
        #expect(HotkeyCommand(url: try #require(URL(string: "eyetracking://toggle"))) == .toggle)
        #expect(HotkeyCommand(url: try #require(URL(string: "EyeTracking://Pause-Start"))) == .pauseStart)
        #expect(HotkeyCommand(url: try #require(URL(string: "eyetracking://unknown"))) == nil)
        #expect(HotkeyCommand(url: try #require(URL(string: "https://toggle"))) == nil)
        for command in HotkeyCommand.allCases {
            #expect(HotkeyCommand(url: command.url) == command)
        }
    }

    @Test("Settings round-trip and tolerate missing or broken files")
    func settings() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sub/settings.json")
        let store = SettingsStore(fileURL: file, log: Log("Test", sink: CaptureSink()))
        #expect(store.load() == Settings())
        try store.update {
            $0.notifiedUpdate = "0.1.1"
            $0.cameraRotations = ["phone": 90]
        }
        #expect(SettingsStore(fileURL: file).load().notifiedUpdate == "0.1.1")
        #expect(SettingsStore(fileURL: file).load().cameraRotations == ["phone": 90])
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(text.contains(#""notified_update" : "0.1.1""#))

        try Data("{\"unknown\": 1}".utf8).write(to: file)
        #expect(SettingsStore(fileURL: file).load() == Settings())
        try Data("not json".utf8).write(to: file)
        let sink = CaptureSink()
        #expect(SettingsStore(fileURL: file, log: Log("Test", sink: sink)).load() == Settings())
        #expect(sink.entries.first?.level == .warning)
    }

    @Test("Log lines carry timestamp, padded level, category and message")
    func logLine() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let line = RotatingLogFile.formatLine(
            date: Date(timeIntervalSince1970: 1_790_000_000.25), level: .info, category: "App", message: "hi",
            timeZone: utc)
        #expect(line == "2026-09-21 14:13:20,250 [INFO    ] App: hi\n")
    }

    @Test("The log file rotates before reaching the size limit")
    func logRotation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = RotatingLogFile(directory: root, maxBytes: 120, backupCount: 2)
        for index in 0..<6 {
            file.write(level: .info, category: "T", message: "message number \(index)")
        }
        #expect(FileManager.default.fileExists(atPath: file.backupURL(1).path))
        #expect(FileManager.default.fileExists(atPath: file.backupURL(2).path))
        #expect(!FileManager.default.fileExists(atPath: file.backupURL(3).path))
    }

    @Test("App locations that cannot be updated in place")
    func appLocation() {
        #expect(AppLocation.problem(bundlePath: "/usr/bin/swift") == .notBundled)
        #expect(AppLocation.problem(bundlePath: "/Volumes/EyeTracking/Eye Tracking.app") == .needsApplicationsFolder)
        #expect(AppLocation.problem(bundlePath: "/Applications/Eye Tracking.app") == nil)
    }

    @Test("Excerpts are trimmed and cut")
    func excerpt() {
        #expect(TextLimits.excerpt("  abcdef \n", 3) == "abc")
        #expect(TextLimits.excerpt("ab", 10) == "ab")
    }
}
