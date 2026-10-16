import AppKit

/// The application main menu.
///
/// A menu bar app never shows it, but AppKit routes key equivalents such as Command-V through it; without an Edit
/// menu, text fields in alerts cannot paste, copy, cut, select all or undo.
@MainActor
enum MainMenu {
    /// Builds the main menu with the standard Edit commands.
    ///
    /// - Returns: The menu to assign to `NSApplication.mainMenu`.
    static func make() -> NSMenu {
        let edit = NSMenu(title: String(localized: "edit.menu"))
        edit.addItem(item("edit.undo", action: Selector(("undo:")), key: "z"))
        edit.addItem(item("edit.redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("edit.cut", action: #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(item("edit.copy", action: #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(item("edit.paste", action: #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(item("edit.select_all", action: #selector(NSText.selectAll(_:)), key: "a"))
        let editItem = NSMenuItem(title: edit.title, action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        return main
    }

    private static func item(
        _ key: String.LocalizationValue,
        action: Selector,
        key equivalent: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: key), action: action, keyEquivalent: equivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
