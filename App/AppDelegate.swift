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
    private var pointer: PointerController?
    private var calibration: CalibrationController?
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
        let pointer = PointerController(gaze: gaze, settings: settings)
        gaze.onDisplaysChanged = { [weak gazeDot, weak pointer] in
            gazeDot?.displaysChanged()
            pointer?.displaysChanged()
        }
        calibration.onStart = { [weak gazeDot, weak pointer] in
            gazeDot?.hide()
            pointer?.setSuspended(true)
        }
        calibration.onFinish = { [weak pointer] in pointer?.setSuspended(false) }
        tracking.onCameraChanged = { [weak gaze] in gaze?.cameraChanged() }
        let menuActions = MenuActions(
            updater: updater, tracking: tracking, preview: preview, gaze: gaze, calibration: calibration,
            gazeDot: gazeDot, pointer: pointer)
        let statusItemController = StatusItemController(actions: menuActions)
        self.updater = updater
        self.tracking = tracking
        self.menuActions = menuActions
        self.pointer = pointer
        self.calibration = calibration
        self.statusItemController = statusItemController
        updater.start()
        pointer.restore()
        if gaze.needsRecalibration {
            log.info("The saved calibration is outdated.")
            let calibrate = Alerts.choose(
                String(localized: "calibration.outdated.title"), String(localized: "calibration.outdated.message"),
                primary: String(localized: "calibration.outdated.now"),
                secondary: String(localized: "calibration.outdated.later"))
            if calibrate {
                calibration.start()
            }
        }
    }

    /// Handles the hotkey URLs that Karabiner opens with `open -g eyetracking://...`.
    ///
    /// - Parameters:
    ///   - application: The application.
    ///   - urls: The opened URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = HotkeyCommand(url: url) else {
                log.warning("Unknown URL \(url.absoluteString).")
                continue
            }
            log.info("Hotkey: \(command).")
            switch command {
            case .toggle:
                pointer?.toggle()
            case .pauseStart:
                pointer?.setPaused(true)
            case .pauseEnd:
                pointer?.setPaused(false)
            case .recalibrate:
                calibration?.start()
            }
        }
    }

    /// Gives the mouse back and stops the periodic update check before the app quits.
    ///
    /// - Parameter notification: The termination notification.
    func applicationWillTerminate(_ notification: Notification) {
        pointer?.shutDown()
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
