import AppKit
import AppSupportKit
import CoreKit

/// Application delegate that owns the services and the menu bar controller for the lifetime of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Log("App")
    private var updater: Updater?
    private var tracking: TrackingController?
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
        let settings = SettingsStore()
        let updater = Updater(settings: settings, notifier: notifier)
        let tracking = TrackingController(settings: settings)
        let preview = PreviewWindowController(tracking: tracking)
        let gaze = GazeService(tracking: tracking)
        let gazeDot = GazeDotController(gaze: gaze)
        let calibration = CalibrationController(tracking: tracking, gaze: gaze)
        gaze.onDisplaysChanged = { [weak gazeDot] in gazeDot?.displaysChanged() }
        calibration.onStart = { [weak gazeDot] in gazeDot?.hide() }
        let menuActions = MenuActions(
            updater: updater, tracking: tracking, preview: preview, gaze: gaze, calibration: calibration,
            gazeDot: gazeDot)
        let statusItemController = StatusItemController(actions: menuActions)
        self.updater = updater
        self.tracking = tracking
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
