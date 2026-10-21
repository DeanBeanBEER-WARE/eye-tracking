import AVFoundation
import AppKit
import AppSupportKit
import CoreKit
import TrackingKit

enum CameraStatus: Equatable {
    case waiting(String)

    case paused(String)

    case running(String)
}

@MainActor
final class TrackingController {
    enum Consumer: Hashable {
        case preview

        case calibration

        case gaze
    }

    private static let healthInterval: Duration = .seconds(2)
    private static let stallRestart: Duration = .seconds(6)
    private static let firstFrameAlert: Duration = .seconds(10)

    private let settings: SettingsStore
    private let log = Log("Tracking")
    private var consumers: Set<Consumer> = []
    private var observers: [Consumer: (FaceObservation?) -> Void] = [:]
    private var gate = CameraStartGate()
    private var health: Task<Void, Never>?
    private var connectObserver: NSObjectProtocol?
    private var isWaitingForCamera = false
    private var isSuspended = false

    let engine: TrackingEngine

    var onCameraChanged: (() -> Void)?

    var onStatusChanged: ((CameraStatus) -> Void)?

    private(set) var status = CameraStatus.waiting("") {
        didSet {
            if status != oldValue {
                onStatusChanged?(status)
            }
        }
    }

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
        engine.setCameraEventHandler { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            }
        }
        engine.setRotationLockedHandler { [weak self] offset in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.remember(rotation: offset)
                }
            }
        }
        connectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let id = (notification.object as? AVCaptureDevice)?.uniqueID
            MainActor.assumeIsolated {
                self?.cameraConnected(id)
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
        let selected = settings.load().cameraID
        return selected.isEmpty ? CameraCapture.devices().first?.id ?? "" : selected
    }

    var activeCameraName: String {
        cameraChoices.first { $0.isSelected }?.name ?? settings.load().cameraName
    }

    var cameraChoices: [CameraChoice] {
        let devices = CameraCapture.devices()
        let stored = settings.load()
        let active = stored.cameraID.isEmpty ? devices.first?.id ?? "" : stored.cameraID
        var choices = devices.map { CameraChoice(id: $0.id, name: $0.name, isSelected: $0.id == active) }
        if !active.isEmpty, !devices.contains(where: { $0.id == active }) {
            let name = stored.cameraName.isEmpty ? active : stored.cameraName
            choices.append(
                CameraChoice(id: active, name: String(localized: "camera.not_connected \(name)"), isSelected: true))
        }
        return choices
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
        isWaitingForCamera = false
        perform(gate.release())
    }

    func selectCamera(_ id: String) {
        let name = CameraCapture.devices().first { $0.id == id }?.name ?? ""
        do {
            try settings.update {
                $0.cameraID = id
                $0.cameraName = name
            }
        } catch {
            log.error("Could not save the camera: \(error)")
        }
        log.info("Camera selected: \(name).")
        isSuspended = false
        status = .waiting(name)
        onCameraChanged?()
        if isWaitingForCamera {
            isWaitingForCamera = false
            perform(gate.demand())
        } else {
            perform(gate.switchCamera())
        }
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
            health?.cancel()
            let engine = engine
            Task.detached { engine.stop() }
        }
    }

    private func launch(restart: Bool) {
        health?.cancel()
        let engine = engine
        let stored = settings.load()
        let deviceID = stored.cameraID.isEmpty ? nil : stored.cameraID
        let rotation = deviceID.flatMap { stored.cameraRotations[$0] } ?? 0
        status = .waiting(activeCameraName)
        Task {
            guard await CameraCapture.requestAccess() else {
                gate.startFailed()
                log.warning("Camera access denied.")
                Alerts.info(String(localized: "camera.denied.title"), String(localized: "camera.denied.message"))
                return
            }
            let failure = await Task.detached { () -> CameraFailure? in
                do {
                    if restart {
                        try engine.restart(deviceID: deviceID, rotationOffset: rotation)
                    } else {
                        try engine.start(deviceID: deviceID, rotationOffset: rotation)
                    }
                    return nil
                } catch let error as CameraError where error == .deviceUnavailable {
                    return .unavailable
                } catch {
                    return .failed(String(describing: error))
                }
            }.value
            switch failure {
            case .unavailable:
                gate.startFailed()
                isWaitingForCamera = !consumers.isEmpty
                log.info("Waiting for \(activeCameraName) to connect.")
                return
            case .failed(let message):
                gate.startFailed()
                log.error("Tracking could not start: \(message)")
                Alerts.info(String(localized: "tracking.failed.title"), message)
                return
            case nil:
                break
            }
            isWaitingForCamera = false
            let next = gate.startSucceeded(hasConsumers: !consumers.isEmpty)
            if next == .none {
                status = isSuspended ? .paused(activeCameraName) : .running(activeCameraName)
                monitorHealth()
            }
            perform(next)
        }
    }

    private enum CameraFailure {
        case unavailable
        case failed(String)
    }

    private func monitorHealth() {
        let engine = engine
        health = Task {
            let clock = ContinuousClock()
            let started = clock.now
            var lastCount = engine.frameCount
            var lastProgress = clock.now
            var alerted = false
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.healthInterval)
                guard !Task.isCancelled, gate.isRunning else {
                    continue
                }
                let count = engine.frameCount
                if count != lastCount {
                    lastCount = count
                    lastProgress = clock.now
                    if !isSuspended {
                        status = .running(activeCameraName)
                    }
                    continue
                }
                if count == 0, !alerted, clock.now - started >= Self.firstFrameAlert {
                    alerted = true
                    log.warning("\(activeCameraName) delivered no frame within 10 seconds.")
                    Alerts.info(
                        String(localized: "camera.no_frames.title \(activeCameraName)"),
                        String(localized: "camera.no_frames.message"))
                }
                guard !isSuspended, clock.now - lastProgress >= Self.stallRestart else {
                    continue
                }
                log.warning("No frames from \(activeCameraName) for 6 seconds; restarting the camera.")
                status = .waiting(activeCameraName)
                perform(gate.switchCamera())
                return
            }
        }
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case .suspended(let suspended):
            isSuspended = suspended
            status = suspended ? .paused(activeCameraName) : .waiting(activeCameraName)
        case .interrupted:
            status = .paused(activeCameraName)
        case .interruptionEnded:
            status = .waiting(activeCameraName)
        case .disconnected, .runtimeError:
            status = .waiting(activeCameraName)
            guard gate.isRunning else {
                return
            }
            health?.cancel()
            isWaitingForCamera = true
            perform(gate.release())
        }
    }

    private func cameraConnected(_ id: String?) {
        guard let id, id == settings.load().cameraID, isWaitingForCamera, !consumers.isEmpty else {
            return
        }
        log.info("\(activeCameraName) connected again; starting it.")
        isWaitingForCamera = false
        perform(gate.demand())
    }

    private func remember(rotation offset: Int) {
        let id = activeCameraID
        guard !id.isEmpty, settings.load().cameraRotations[id] != offset else {
            return
        }
        do {
            try settings.update { $0.cameraRotations[id] = offset }
        } catch {
            log.error("Could not save the camera rotation: \(error)")
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
