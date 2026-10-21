import Foundation
import os

public struct Settings: Codable, Equatable, Sendable {
    public var notifiedUpdate: String

    public var cameraID: String

    public var gazeControl: Bool

    public var snapping: Bool

    public var cameraName: String

    public var cameraRotations: [String: Int]

    public init(
        notifiedUpdate: String = "", cameraID: String = "", gazeControl: Bool = false, snapping: Bool = true,
        cameraName: String = "", cameraRotations: [String: Int] = [:]
    ) {
        self.notifiedUpdate = notifiedUpdate
        self.cameraID = cameraID
        self.gazeControl = gazeControl
        self.snapping = snapping
        self.cameraName = cameraName
        self.cameraRotations = cameraRotations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifiedUpdate = try container.decodeIfPresent(String.self, forKey: .notifiedUpdate) ?? ""
        cameraID = try container.decodeIfPresent(String.self, forKey: .cameraID) ?? ""
        gazeControl = try container.decodeIfPresent(Bool.self, forKey: .gazeControl) ?? false
        snapping = try container.decodeIfPresent(Bool.self, forKey: .snapping) ?? true
        cameraName = try container.decodeIfPresent(String.self, forKey: .cameraName) ?? ""
        cameraRotations = try container.decodeIfPresent([String: Int].self, forKey: .cameraRotations) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case notifiedUpdate = "notified_update"
        case cameraID = "camera_id"
        case gazeControl = "gaze_control"
        case snapping
        case cameraName = "camera_name"
        case cameraRotations = "camera_rotations"
    }
}

public final class SettingsStore: Sendable {
    public let fileURL: URL

    private let log: Log
    private let cache = OSAllocatedUnfairLock<Settings?>(initialState: nil)

    public init(fileURL: URL = Paths.standard.settingsFile, log: Log = Log("Settings")) {
        self.fileURL = fileURL
        self.log = log
    }

    public func load() -> Settings {
        if let cached = cache.withLock({ $0 }) {
            return cached
        }
        let settings = read()
        cache.withLock { $0 = settings }
        return settings
    }

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
