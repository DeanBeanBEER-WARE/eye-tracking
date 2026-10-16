import AppKit

/// Modal information and confirmation alerts of the menu actions.
@MainActor
public enum Alerts {
    /// Shows an alert with an OK button.
    ///
    /// - Parameters:
    ///   - title: The bold title.
    ///   - message: The explanation below the title.
    public static func info(_ title: String, _ message: String = "") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "alert.ok"))
        NSApp.activate()
        alert.runModal()
    }

    /// Asks the user to choose between two actions.
    ///
    /// - Parameters:
    ///   - title: The bold title.
    ///   - message: The explanation below the title.
    ///   - primary: The title of the default button.
    ///   - secondary: The title of the second button.
    /// - Returns: `true` if the user pressed the default button.
    public static func choose(_ title: String, _ message: String, primary: String, secondary: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: primary)
        alert.addButton(withTitle: secondary)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
