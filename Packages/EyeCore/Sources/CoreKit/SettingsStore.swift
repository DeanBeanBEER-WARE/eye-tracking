import Foundation
import os

/// The persisted settings of the app.
///
/// Unknown or missing keys fall back to the defaults, so older and newer settings files stay readable.
public struct Settings: Codable, Equatable, Sendable {
    /// The display version of the last release an update notification was posted for, empty if none.
    public var notifiedUpdate: String

    /// The unique identifier of the tracking camera, empty for the built-in camera.
    public var cameraID: String

    /// Whether gaze control was on when the app last ran; it is switched on again at launch.
    public var gazeControl: Bool

    /// Whether the cursor snaps to clickable elements after the gaze landed.
    public var snapping: Bool

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - notifiedUpdate: The display version of the last announced release.
    ///   - cameraID: The identifier of the tracking camera, empty for the built-in camera.
    ///   - gazeControl: Whether gaze control is on.
    ///   - snapping: Whether the cursor snaps to clickable elements.
    public init(
        notifiedUpdate: String = "", cameraID: String = "", gazeControl: Bool = false, snapping: Bool = true
    ) {
        self.notifiedUpdate = notifiedUpdate
        self.cameraID = cameraID
        self.gazeControl = gazeControl
        self.snapping = snapping
    }

    /// Decodes settings, using the default for every missing key.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if a present key has the wrong type.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifiedUpdate = try container.decodeIfPresent(String.self, forKey: .notifiedUpdate) ?? ""
        cameraID = try container.decodeIfPresent(String.self, forKey: .cameraID) ?? ""
        gazeControl = try container.decodeIfPresent(Bool.self, forKey: .gazeControl) ?? false
        snapping = try container.decodeIfPresent(Bool.self, forKey: .snapping) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case notifiedUpdate = "notified_update"
        case cameraID = "camera_id"
        case gazeControl = "gaze_control"
        case snapping
    }
}

/// Loads and saves ``Settings`` as a JSON file.
public final class SettingsStore: Sendable {
    /// The settings file.
    public let fileURL: URL

    private let log: Log
    private let cache = OSAllocatedUnfairLock<Settings?>(initialState: nil)

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - fileURL: The settings file.
    ///   - log: The logger.
    public init(fileURL: URL = Paths.standard.settingsFile, log: Log = Log("Settings")) {
        self.fileURL = fileURL
        self.log = log
    }

    /// Returns the settings, reading the file on the first call.
    ///
    /// A missing file gives the defaults; an unreadable file is logged and gives the defaults too.
    ///
    /// - Returns: The current settings.
    public func load() -> Settings {
        if let cached = cache.withLock({ $0 }) {
            return cached
        }
        let settings = read()
        cache.withLock { $0 = settings }
        return settings
    }

    /// Changes the settings and writes the file atomically.
    ///
    /// - Parameter change: Modifies the settings.
    /// - Throws: The file system error if the file cannot be written.
    public func update(_ change: (inout Settings) -> Void) throws {
        var changed = load()
        change(&changed)
        let settings = changed
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        cache.withLock { $0 = settings }
    }

    private func read() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else {
            return Settings()
        }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            log.warning("Unreadable settings file \(fileURL.path), using defaults: \(error)")
            return Settings()
        }
    }
}
