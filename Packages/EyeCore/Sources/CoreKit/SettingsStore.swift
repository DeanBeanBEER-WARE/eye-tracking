import Foundation
import os

/// The persisted settings of the app.
///
/// Unknown or missing keys fall back to the defaults, so older and newer settings files stay readable.
public struct Settings: Codable, Equatable, Sendable {
    /// The display version of the last release an update notification was posted for, empty if none.
    public var notifiedUpdate: String

    /// Creates settings.
    ///
    /// - Parameter notifiedUpdate: The display version of the last announced release.
    public init(notifiedUpdate: String = "") {
        self.notifiedUpdate = notifiedUpdate
    }

    /// Decodes settings, using the default for every missing key.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if a present key has the wrong type.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifiedUpdate = try container.decodeIfPresent(String.self, forKey: .notifiedUpdate) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case notifiedUpdate = "notified_update"
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
