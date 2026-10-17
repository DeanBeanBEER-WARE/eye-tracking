import Foundation

public struct Paths: Sendable {
    public static let standard = Paths(home: FileManager.default.homeDirectoryForCurrentUser)

    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public var supportDirectory: URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(AppInfo.directoryName, isDirectory: true)
    }

    public var settingsFile: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }

    public var emptyCABundle: URL {
        supportDirectory.appendingPathComponent("mediapipe-no-upload.pem")
    }

    public var logDirectory: URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppInfo.directoryName, isDirectory: true)
    }

    public var updateLogFile: URL {
        logDirectory.appendingPathComponent("update.log")
    }
}
