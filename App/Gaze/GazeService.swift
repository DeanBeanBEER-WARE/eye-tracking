import AppKit
import CoreKit
import GazeKit
import TrackingKit

enum GazeUpdate {
    case estimate(GazeEstimate)

    case blink

    case noFace
}

@MainActor
final class GazeService {
    enum Listener: Hashable {
        case dot

        case pointer
    }

    private let tracking: TrackingController
    private let store = CalibrationStore()
    private let log = Log("Gaze")
    private var saved: GazeModel?
    private var layoutSignature = DisplayLayoutReader.current().signature
    private var cameraID = ""
    private var estimator: GazeEstimator?
    private var listeners: [Listener: (GazeUpdate) -> Void] = [:]
    private var screenObserver: NSObjectProtocol?

    var onDisplaysChanged: (() -> Void)?

    init(tracking: TrackingController) {
        self.tracking = tracking
        cameraID = tracking.activeCameraID
        saved = store.load()
        if let saved {
            log.info(
                "Calibration from \(saved.createdAt) loaded; "
                    + (saved.layout.signature == layoutSignature ? "it matches the displays" : "the displays changed")
                    + (saved.isCurrent ? "." : ", but it uses an older feature version."))
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displaysChanged()
            }
        }
    }

    var model: GazeModel? {
        guard let saved, saved.isCurrent, saved.layout.signature == layoutSignature,
            saved.data.cameraID == nil || saved.data.cameraID == cameraID
        else {
            return nil
        }
        return saved
    }

    func cameraChanged() {
        cameraID = tracking.activeCameraID
        log.info("Camera changed; calibration \(model == nil ? "does not match" : "matches").")
        estimator = model.map(GazeEstimator.init(model:))
        onDisplaysChanged?()
    }

    var needsRecalibration: Bool {
        saved.map { !$0.isCurrent } ?? false
    }

    func install(_ model: GazeModel) throws {
        try store.save(model)
        saved = model
        layoutSignature = DisplayLayoutReader.current().signature
        cameraID = tracking.activeCameraID
        estimator = self.model.map(GazeEstimator.init(model:))
        log.info("Calibration saved (lambda \(model.lambda), \(model.data.samples.count) samples).")
    }

    func subscribe(_ listener: Listener, _ handler: @escaping (GazeUpdate) -> Void) {
        let first = listeners.isEmpty
        listeners[listener] = handler
        guard first else {
            return
        }
        estimator = model.map(GazeEstimator.init(model:))
        tracking.setObserver(.gaze) { [weak self] observation in
            self?.handle(observation)
        }
        tracking.acquire(.gaze)
    }

    func unsubscribe(_ listener: Listener) {
        guard listeners.removeValue(forKey: listener) != nil, listeners.isEmpty else {
            return
        }
        tracking.setObserver(.gaze, nil)
        tracking.release(.gaze)
        estimator = nil
    }

    private func handle(_ observation: FaceObservation?) {
        let update: GazeUpdate
        if estimator != nil, let observation, let features = FeatureExtractor.extract(observation) {
            if let estimate = estimator?.update(features) {
                update = .estimate(estimate)
            } else {
                update = .blink
            }
        } else {
            estimator?.reset()
            update = .noFace
        }
        for handler in listeners.values {
            handler(update)
        }
    }

    private func displaysChanged() {
        let signature = DisplayLayoutReader.current().signature
        guard signature != layoutSignature else {
            return
        }
        layoutSignature = signature
        log.info("Displays changed: \(signature); calibration \(model == nil ? "does not match" : "matches").")
        estimator = model.map(GazeEstimator.init(model:))
        onDisplaysChanged?()
    }
}
