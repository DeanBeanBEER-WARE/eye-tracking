import Foundation

public enum HotkeyCommand: String, Equatable, Sendable, CaseIterable {
    case toggle

    case pauseStart = "pause-start"

    case pauseEnd = "pause-end"

    case recalibrate

    public static let scheme = "eyetracking"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else {
            return nil
        }
        self.init(rawValue: host)
    }

    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }
}
