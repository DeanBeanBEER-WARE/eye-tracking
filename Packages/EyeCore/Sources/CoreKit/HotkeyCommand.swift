import Foundation

/// A command sent by a hotkey as a URL, for example by Karabiner with `open -g eyetracking://toggle`.
public enum HotkeyCommand: String, Equatable, Sendable, CaseIterable {
    /// Switches gaze control on or off.
    case toggle

    /// Pauses gaze control until ``pauseEnd``; the mouse works normally meanwhile.
    case pauseStart = "pause-start"

    /// Ends the pause.
    case pauseEnd = "pause-end"

    /// Starts a calibration.
    case recalibrate

    /// The URL scheme of the app.
    public static let scheme = "eyetracking"

    /// Reads a command from a URL; fails for another scheme or an unknown command.
    ///
    /// - Parameter url: The URL, `eyetracking://<command>`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else {
            return nil
        }
        self.init(rawValue: host)
    }

    /// The URL that sends the command.
    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }
}
