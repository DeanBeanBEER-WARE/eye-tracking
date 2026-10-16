import CoreKit
import Foundation

/// The localized titles of the status menu entries.
enum MenuStrings {
    /// Returns the title of an entry.
    ///
    /// - Parameter label: The label of the entry.
    /// - Returns: The localized title.
    static func text(_ label: MenuLabel) -> String {
        switch label {
        case .version(let version):
            String(localized: "menu.version \(AppInfo.displayName) \(version)")
        case .checkForUpdates:
            String(localized: "menu.check_updates")
        case .checkingForUpdates:
            String(localized: "menu.checking_updates")
        case .installUpdate(let version):
            String(localized: "menu.install_update \(version)")
        case .quit:
            String(localized: "menu.quit")
        }
    }
}
