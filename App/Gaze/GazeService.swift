import AppKit
import CoreKit
import GazeKit
import TrackingKit

/// What a gaze listener receives for one camera frame.
enum GazeUpdate {
    /// The smoothed gaze point.
    case estimate(GazeEstimate)

    /// The eyes are closed; the last estimate still holds.
    case blink

    /// No face is visible.
    case noFace
}

/// Holds the calibrated gaze model and turns tracking results into gaze estimates while a listener needs them.
@MainActor
final class GazeService {
    /// A part of the app that listens to gaze estimates.
    enum Listener: Hashable {
        /// The live gaze dot.
        case dot

        /// Gaze control of the pointer.
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

    /// Called when the displays or the camera change, after the model was checked against them.
    var onDisplaysChanged: (() -> Void)?

    /// Loads the saved calibration.
    ///
    /// - Parameter tracking: Delivers the tracking results.
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

    /// The model, if one is calibrated for the current display arrangement and feature version.
    var model: GazeModel? {
        guard let saved, saved.isCurrent, saved.layout.signature == layoutSignature,
            saved.data.cameraID == nil || saved.data.cameraID == cameraID
        else {
            return nil
        }
        return saved
    }

    /// Follows a switch to another camera; a calibration belongs to the camera it was recorded with.
    func cameraChanged() {
        cameraID = tracking.activeCameraID
        log.info("Camera changed; calibration \(model == nil ? "does not match" : "matches").")
        estimator = model.map(GazeEstimator.init(model:))
        onDisplaysChanged?()
    }

    /// Whether the saved calibration was made with an older feature version and must be repeated.
    var needsRecalibration: Bool {
        saved.map { !$0.isCurrent } ?? false
    }

    /// Saves a new model and uses it from now on.
    ///
    /// - Parameter model: The fitted model.
    /// - Throws: The file system error of saving.
    func install(_ model: GazeModel) throws {
        try store.save(model)
        saved = model
        layoutSignature = DisplayLayoutReader.current().signature
        cameraID = tracking.activeCameraID
        estimator = self.model.map(GazeEstimator.init(model:))
        log.info("Calibration saved (lambda \(model.lambda), \(model.data.samples.count) samples).")
    }

    /// Starts sending gaze updates to a listener; tracking runs while any listener is registered.
    ///
    /// - Parameters:
    ///   - listener: The listener.
    ///   - handler: Called on the main thread for every frame.
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

    /// Stops sending gaze updates to a listener.
    ///
    /// - Parameter listener: The listener.
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
