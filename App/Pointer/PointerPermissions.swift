import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid

enum PointerPermissions {
    static var canPostEvents: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    static var canListen: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestPostEvents() {
        if !AXIsProcessTrusted() {
            ElementSnapper.requestTrust()
        }
    }

    static func requestListen() {
        if !canListen {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
