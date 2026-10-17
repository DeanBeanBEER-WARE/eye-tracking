import AppKit
import CoreKit

final class MenuCommandBox: NSObject {
    let command: MenuCommand

    init(_ command: MenuCommand) {
        self.command = command
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let iconSize = NSSize(width: 18, height: 18)

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let actions: MenuActions

    init(actions: MenuActions) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.actions = actions
        super.init()
        configureButton()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in items(MenuModel.build(state: actions.state())) {
            menu.addItem(item)
        }
    }

    private func items(_ nodes: [MenuNode]) -> [NSMenuItem] {
        nodes.map { node in
            switch node {
            case .separator:
                return .separator()
            case .item(let entry):
                return item(entry)
            case .submenu(let label, let children):
                let title = MenuStrings.text(label)
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                for child in items(children) {
                    submenu.addItem(child)
                }
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = submenu
                return item
            }
        }
    }

    private func item(_ entry: MenuItem) -> NSMenuItem {
        let item = NSMenuItem(
            title: MenuStrings.text(entry.label), action: nil, keyEquivalent: entry.keyEquivalent)
        item.state = entry.isChecked ? .on : .off
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
