import AppKit
import CoreKit

/// Provides the state of the status menu and performs its commands.
@MainActor
final class MenuActions: NSObject {
    private let updater: Updater
    private let tracking: TrackingController
    private let preview: PreviewWindowController
    private let gaze: GazeService
    private let calibration: CalibrationController
    private let gazeDot: GazeDotController
    private let pointer: PointerController

    /// Creates the actions.
    ///
    /// - Parameters:
    ///   - updater: Checks for and installs releases.
    ///   - tracking: Runs the camera and lists the cameras.
    ///   - preview: The camera preview window.
    ///   - gaze: Holds the calibrated model.
    ///   - calibration: Runs calibrations.
    ///   - gazeDot: Shows the live gaze point.
    ///   - pointer: Gaze control of the pointer.
    init(
        updater: Updater, tracking: TrackingController, preview: PreviewWindowController, gaze: GazeService,
        calibration: CalibrationController, gazeDot: GazeDotController, pointer: PointerController
    ) {
        self.updater = updater
        self.tracking = tracking
        self.preview = preview
        self.gaze = gaze
        self.calibration = calibration
        self.gazeDot = gazeDot
        self.pointer = pointer
    }

    /// The current state of the status menu.
    ///
    /// - Returns: The state the menu is built from.
    func state() -> MenuState {
        MenuState(
            version: AppVersion.current,
            availableUpdate: updater.availableUpdate,
            isCheckingForUpdates: updater.isChecking,
            isPreviewVisible: preview.isVisible,
            cameras: tracking.cameraChoices,
            hasCalibration: gaze.model != nil,
            isCalibrating: calibration.isRunning,
            isGazeDotVisible: gazeDot.isVisible,
            isGazeControlOn: pointer.isEnabled
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
        case .toggleGazeControl:
            pointer.toggle()
        case .calibrate:
            calibration.start()
        case .toggleGazeDot:
            gazeDot.toggle()
        case .togglePreview:
            preview.toggle()
        case .selectCamera(let id):
            tracking.selectCamera(id)
        case .checkForUpdates:
            updater.checkManually()
        case .installUpdate:
            updater.installAvailable()
        case .showLog:
            NSWorkspace.shared.open(Paths.standard.logDirectory.appendingPathComponent(RotatingLogFile.defaultFileName))
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
