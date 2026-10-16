import AppKit
import CoreKit

/// Carries the command of a menu item in its `representedObject`.
final class MenuCommandBox: NSObject {
    /// The command performed when the item is clicked.
    let command: MenuCommand

    /// Wraps a command.
    ///
    /// - Parameter command: The command.
    init(_ command: MenuCommand) {
        self.command = command
    }
}

/// Owns the menu bar status item and rebuilds its menu every time it opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let iconSize = NSSize(width: 18, height: 18)

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let actions: MenuActions

    /// Creates the status item with the template icon and an empty menu that is filled on demand.
    ///
    /// - Parameter actions: Provides the menu state and performs the clicked commands.
    init(actions: MenuActions) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.actions = actions
        super.init()
        configureButton()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Rebuilds the menu right before it is shown.
    ///
    /// - Parameter menu: The menu that is about to open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for node in MenuModel.build(state: actions.state()) {
            switch node {
            case .separator:
                menu.addItem(.separator())
            case .item(let entry):
                menu.addItem(item(entry))
            }
        }
    }

    private func item(_ entry: MenuItem) -> NSMenuItem {
        let item = NSMenuItem(
            title: MenuStrings.text(entry.label), action: nil, keyEquivalent: entry.keyEquivalent)
        if let command = entry.command {
            item.action = #selector(MenuActions.performCommand(_:))
            item.target = actions
            item.representedObject = MenuCommandBox(command)
            item.isEnabled = true
        } else {
            item.isEnabled = false
        }
        return item
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = Self.iconSize
        button.image = image
        button.toolTip = AppInfo.displayName
    }
}
