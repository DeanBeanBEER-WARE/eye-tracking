import AppKit
import GazeKit

/// Shows the live gaze point as a dot above all windows, to judge the calibration.
@MainActor
final class GazeDotController {
    private let gaze: GazeService
    private var overlay: OverlaySet?
    private var content = OverlayContent()

    /// Whether the dot is shown.
    var isVisible: Bool {
        overlay != nil
    }

    /// Creates the controller.
    ///
    /// - Parameter gaze: Delivers the gaze estimates.
    init(gaze: GazeService) {
        self.gaze = gaze
    }

    /// Shows the dot, or hides it if it is shown.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Shows the dot if a calibration for the current displays exists.
    func show() {
        guard overlay == nil, gaze.model != nil else {
            return
        }
        let overlay = OverlaySet(interactive: false)
        overlay.show()
        self.overlay = overlay
        content = OverlayContent()
        gaze.subscribe(.dot) { [weak self] update in
            self?.apply(update)
        }
    }

    /// Hides the dot.
    func hide() {
        gaze.unsubscribe(.dot)
        overlay?.close()
        overlay = nil
    }

    /// Rebuilds the windows for new displays, or hides the dot if the calibration no longer fits.
    func displaysChanged() {
        guard isVisible else {
            return
        }
        hide()
        show()
    }

    private func apply(_ update: GazeUpdate) {
        switch update {
        case .estimate(let estimate):
            content.gazeDot = estimate.point
        case .blink:
            return
        case .noFace:
            content.gazeDot = nil
        }
        overlay?.update(content)
    }
}
