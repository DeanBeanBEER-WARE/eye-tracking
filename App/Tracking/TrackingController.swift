import AppKit
import AppSupportKit
import CoreKit
import TrackingKit

/// Owns the tracking engine and runs the camera only while at least one consumer needs it.
@MainActor
final class TrackingController {
    /// A part of the app that needs tracking results.
    enum Consumer: Hashable {
        /// The camera preview window.
        case preview

        /// The calibration.
        case calibration

        /// The gaze estimation (gaze dot, pointer).
        case gaze
    }

    private let settings: SettingsStore
    private let log = Log("Tracking")
    private var consumers: Set<Consumer> = []
    private var observers: [Consumer: (FaceObservation?) -> Void] = [:]
    private var startTask: Task<Void, Never>?
    private var isRunning = false

    /// The tracking pipeline.
    let engine: TrackingEngine

    /// Creates the controller with the MediaPipe files of the app bundle.
    ///
    /// - Parameter settings: Provides the selected camera.
    init(settings: SettingsStore) {
        self.settings = settings
        engine = TrackingEngine(resources: Self.resources())
        engine.setObservationHandler { [weak self] observation in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.deliver(observation)
                }
            }
        }
    }

    /// Sets the receiver of a consumer's tracking results, called on the main thread for every frame
    /// (`nil` for a frame without a face).
    ///
    /// - Parameters:
    ///   - consumer: The consumer.
    ///   - handler: The receiver, or `nil` to remove it.
    func setObserver(_ consumer: Consumer, _ handler: ((FaceObservation?) -> Void)?) {
        observers[consumer] = handler
    }

    private func deliver(_ observation: FaceObservation?) {
        for handler in observers.values {
            handler(observation)
        }
    }

    /// Called after the user switched to another camera.
    var onCameraChanged: (() -> Void)?

    /// The identifier of the camera tracking uses.
    var activeCameraID: String {
        cameraChoices.first { $0.isSelected }?.id ?? ""
    }

    /// The cameras for the camera submenu, with the tracking camera selected.
    var cameraChoices: [CameraChoice] {
        let devices = CameraCapture.devices()
        let selected = settings.load().cameraID
        let active = devices.contains { $0.id == selected } ? selected : devices.first?.id ?? ""
        return devices.map { CameraChoice(id: $0.id, name: $0.name, isSelected: $0.id == active) }
    }

    /// Registers a consumer and starts the camera if it is the first one.
    ///
    /// - Parameter consumer: The consumer.
    func acquire(_ consumer: Consumer) {
        consumers.insert(consumer)
        startIfNeeded()
    }

    /// Unregisters a consumer and stops the camera if none is left.
    ///
    /// - Parameter consumer: The consumer.
    func release(_ consumer: Consumer) {
        consumers.remove(consumer)
        guard consumers.isEmpty else {
            return
        }
        startTask?.cancel()
        startTask = nil
        if isRunning {
            isRunning = false
            let engine = engine
            Task.detached { engine.stop() }
        }
    }

    /// Switches to another camera and restarts tracking if it runs.
    ///
    /// - Parameter id: The camera identifier.
    func selectCamera(_ id: String) {
        do {
            try settings.update { $0.cameraID = id }
        } catch {
            log.error("Could not save the camera: \(error)")
        }
        onCameraChanged?()
        guard isRunning else {
            return
        }
        isRunning = false
        let engine = engine
        Task.detached { engine.stop() }
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !consumers.isEmpty, !isRunning, startTask == nil else {
            return
        }
        let engine = engine
        let cameraID = settings.load().cameraID
        startTask = Task {
            defer { startTask = nil }
            guard await CameraCapture.requestAccess() else {
                log.warning("Camera access denied.")
                Alerts.info(String(localized: "camera.denied.title"), String(localized: "camera.denied.message"))
                return
            }
            let result = await Task.detached { () -> String? in
                do {
                    try engine.start(deviceID: cameraID.isEmpty ? nil : cameraID)
                    return nil
                } catch {
                    return String(describing: error)
                }
            }.value
            if let result {
                log.error("Tracking could not start: \(result)")
                Alerts.info(String(localized: "tracking.failed.title"), result)
                return
            }
            if consumers.isEmpty {
                Task.detached { engine.stop() }
            } else {
                isRunning = true
            }
        }
    }

    private static func resources() -> TrackingResources {
        let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libmediapipe.dylib").path ?? ""
        let model = Bundle.main.url(forResource: "face_landmarker", withExtension: "task")?.path ?? ""
        let caBundle = Paths.standard.emptyCABundle
        try? FileManager.default.createDirectory(
            at: caBundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: caBundle.path) {
            FileManager.default.createFile(atPath: caBundle.path, contents: Data())
        }
        return TrackingResources(libraryPath: library, modelPath: model, caBundlePath: caBundle.path)
    }
}
