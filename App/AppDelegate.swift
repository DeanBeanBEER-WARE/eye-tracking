import AppKit
import AppSupportKit
import CoreKit

/// Application delegate that owns the services and the menu bar controller for the lifetime of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Log("App")
    private var updater: Updater?
    private var menuActions: MenuActions?
    private var statusItemController: StatusItemController?

    /// Starts logging, creates the updater and the status item once the application has finished launching.
    ///
    /// - Parameter notification: The launch notification.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let logFile = RotatingLogFile(directory: Paths.standard.logDirectory)
        Log.bootstrap(logFile)
        NSSetUncaughtExceptionHandler { exception in
            Log("App").critical(
                "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "no reason")\n"
                    + exception.callStackSymbols.joined(separator: "\n")
            )
        }
        log.info("\(AppInfo.displayName) \(AppVersion.current) started (log: \(logFile.fileURL.path)).")
        NSApp.mainMenu = MainMenu.make()
        let notifier = Notifier()
        let updater = Updater(settings: SettingsStore(), notifier: notifier)
        let menuActions = MenuActions(updater: updater)
        let statusItemController = StatusItemController(actions: menuActions)
        self.updater = updater
        self.menuActions = menuActions
        self.statusItemController = statusItemController
        updater.start()
    }

    /// Stops the periodic update check before the app quits.
    ///
    /// - Parameter notification: The termination notification.
    func applicationWillTerminate(_ notification: Notification) {
        updater?.stop()
        log.info("\(AppInfo.displayName) quit.")
    }
}

/// The version of the running app.
enum AppVersion {
    /// The marketing version from the Info.plist.
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
