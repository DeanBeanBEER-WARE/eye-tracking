import AppKit
import CoreKit

/// Provides the state of the status menu and performs its commands.
@MainActor
final class MenuActions: NSObject {
    private let updater: Updater

    /// Creates the actions.
    ///
    /// - Parameter updater: Checks for and installs releases.
    init(updater: Updater) {
        self.updater = updater
    }

    /// The current state of the status menu.
    ///
    /// - Returns: The state the menu is built from.
    func state() -> MenuState {
        MenuState(
            version: AppVersion.current,
            availableUpdate: updater.availableUpdate,
            isCheckingForUpdates: updater.isChecking
        )
    }

    /// Performs the command of a clicked menu item.
    ///
    /// - Parameter sender: The clicked item carrying a ``MenuCommandBox``.
    @objc func performCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuCommandBox else {
            return
        }
        switch box.command {
        case .checkForUpdates:
            updater.checkManually()
        case .installUpdate:
            updater.installAvailable()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
