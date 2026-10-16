import AppKit
import CoreGraphics
import IOKit.hid

/// The privacy permissions of gaze control.
///
/// Posting mouse events needs Accessibility. Seizing a pure mouse interface needs no permission (only keyboards
/// do), so Input Monitoring is only asked for when the system refuses to hand over the mouse.
enum PointerPermissions {
    /// Whether the app may post mouse events.
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// Whether the app may read input devices.
    static var canListen: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Asks the system for Accessibility; macOS shows its prompt and lists the app in the settings.
    static func requestPostEvents() {
        if !canPostEvents {
            _ = CGRequestPostEventAccess()
        }
    }

    /// Asks the system for Input Monitoring.
    static func requestListen() {
        if !canListen {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    /// Opens a privacy pane of the system settings.
    ///
    /// - Parameter pane: `Privacy_Accessibility` or `Privacy_ListenEvent`.
    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
