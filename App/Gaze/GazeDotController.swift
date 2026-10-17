import AppKit
import GazeKit

@MainActor
final class GazeDotController {
    private let gaze: GazeService
    private var overlay: OverlaySet?
    private var content = OverlayContent()

    var isVisible: Bool {
        overlay != nil
    }

    init(gaze: GazeService) {
        self.gaze = gaze
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

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

    func hide() {
        gaze.unsubscribe(.dot)
        overlay?.close()
        overlay = nil
    }

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
