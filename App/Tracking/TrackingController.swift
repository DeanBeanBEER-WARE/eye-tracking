import AppKit
import AppSupportKit
import CoreKit
import TrackingKit

@MainActor
final class TrackingController {
    enum Consumer: Hashable {
        case preview

        case calibration

        case gaze
    }

    private static let firstFrameTimeout: Duration = .seconds(10)

    private let settings: SettingsStore
    private let log = Log("Tracking")
    private var consumers: Set<Consumer> = []
    private var observers: [Consumer: (FaceObservation?) -> Void] = [:]
    private var gate = CameraStartGate()
    private var watchdog: Task<Void, Never>?

    let engine: TrackingEngine

    var onCameraChanged: (() -> Void)?

    var onCameraStarted: ((String) -> Void)?

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

    func setObserver(_ consumer: Consumer, _ handler: ((FaceObservation?) -> Void)?) {
        observers[consumer] = handler
    }

    private func deliver(_ observation: FaceObservation?) {
        for handler in observers.values {
            handler(observation)
        }
    }

    var activeCameraID: String {
        cameraChoices.first { $0.isSelected }?.id ?? ""
    }

    var activeCameraName: String {
        cameraChoices.first { $0.isSelected }?.name ?? ""
    }

    var cameraChoices: [CameraChoice] {
        let devices = CameraCapture.devices()
        let selected = settings.load().cameraID
        let active = devices.contains { $0.id == selected } ? selected : devices.first?.id ?? ""
        return devices.map { CameraChoice(id: $0.id, name: $0.name, isSelected: $0.id == active) }
    }

    func acquire(_ consumer: Consumer) {
        consumers.insert(consumer)
        perform(gate.demand())
    }

    func release(_ consumer: Consumer) {
        consumers.remove(consumer)
        guard consumers.isEmpty else {
            return
        }
        perform(gate.release())
    }

    func selectCamera(_ id: String) {
        do {
            try settings.update { $0.cameraID = id }
        } catch {
            log.error("Could not save the camera: \(error)")
        }
        log.info("Camera selected: \(activeCameraName).")
        onCameraChanged?()
        perform(gate.switchCamera())
    }

    private func perform(_ action: CameraStartGate.Action) {
        switch action {
        case .none:
            return
        case .start:
            launch(restart: false)
        case .restart:
            launch(restart: true)
        case .stop:
            watchdog?.cancel()
            let engine = engine
            Task.detached { engine.stop() }
        }
    }

    private func launch(restart: Bool) {
        watchdog?.cancel()
        let engine = engine
        let cameraID = settings.load().cameraID
        let deviceID = cameraID.isEmpty ? nil : cameraID
        Task {
            guard await CameraCapture.requestAccess() else {
                gate.startFailed()
                log.warning("Camera access denied.")
                Alerts.info(String(localized: "camera.denied.title"), String(localized: "camera.denied.message"))
                return
            }
            let failure = await Task.detached { () -> String? in
                do {
                    if restart {
                        try engine.restart(deviceID: deviceID)
                    } else {
                        try engine.start(deviceID: deviceID)
                    }
                    return nil
                } catch {
                    return String(describing: error)
                }
            }.value
            if let failure {
                gate.startFailed()
                log.error("Tracking could not start: \(failure)")
                Alerts.info(String(localized: "tracking.failed.title"), failure)
                return
            }
            let next = gate.startSucceeded(hasConsumers: !consumers.isEmpty)
            if next == .none {
                let name = engine.cameraName ?? activeCameraName
                onCameraStarted?(name)
                watchFirstFrame(name)
            }
            perform(next)
        }
    }

    private func watchFirstFrame(_ name: String) {
        let engine = engine
        watchdog = Task {
            try? await Task.sleep(for: Self.firstFrameTimeout)
            guard !Task.isCancelled, gate.isRunning, engine.frameCount == 0 else {
                return
            }
            log.warning("\(name) delivered no frame within 10 seconds.")
            Alerts.info(
                String(localized: "camera.no_frames.title \(name)"), String(localized: "camera.no_frames.message"))
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
