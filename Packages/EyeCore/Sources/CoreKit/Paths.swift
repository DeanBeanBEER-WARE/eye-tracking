import Foundation

/// The file system locations of the application.
///
/// Persistent files live under `~/Library/Application Support/EyeTracking`, logs under `~/Library/Logs/EyeTracking`.
public struct Paths: Sendable {
    /// The locations below the current user's home directory.
    public static let standard = Paths(home: FileManager.default.homeDirectoryForCurrentUser)

    /// The home directory all locations are derived from.
    public let home: URL

    /// Creates the locations below a home directory.
    ///
    /// - Parameter home: The home directory, injectable for tests.
    public init(home: URL) {
        self.home = home
    }

    /// The application support directory.
    public var supportDirectory: URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(AppInfo.directoryName, isDirectory: true)
    }

    /// The settings file.
    public var settingsFile: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }

    /// An empty CA bundle handed to MediaPipe so its usage logging cannot upload anything.
    public var emptyCABundle: URL {
        supportDirectory.appendingPathComponent("mediapipe-no-upload.pem")
    }

    /// The log directory.
    public var logDirectory: URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppInfo.directoryName, isDirectory: true)
    }

    /// The log of the detached update script.
    public var updateLogFile: URL {
        logDirectory.appendingPathComponent("update.log")
    }
}
