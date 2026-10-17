import AppKit
import CoreKit

@MainActor
final class MenuActions: NSObject {
    private let updater: Updater
    private let tracking: TrackingController
    private let preview: PreviewWindowController
    private let gaze: GazeService
    private let calibration: CalibrationController
    private let gazeDot: GazeDotController
    private let pointer: PointerController

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
            isGazeControlOn: pointer.isEnabled,
            isSnappingOn: pointer.isSnappingOn
        )
    }

    @objc func performCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuCommandBox else {
            return
        }
        switch box.command {
        case .toggleGazeControl:
            pointer.toggle()
        case .toggleSnapping:
            pointer.toggleSnapping()
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
