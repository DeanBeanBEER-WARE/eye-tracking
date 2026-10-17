import AppKit

@MainActor
public enum Alerts {
    public static func info(_ title: String, _ message: String = "") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "alert.ok"))
        NSApp.activate()
        alert.runModal()
    }

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
