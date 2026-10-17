import AppKit
import AppSupportKit
import CoreKit
import GazeKit
import TrackingKit

@MainActor
final class CalibrationController {
    private enum Stage {
        case intro

        case settle

        case sample
    }

    private static let introTime: TimeInterval = 3

    private static let minimumSamples: [CalibrationTarget.Phase: Int] = [.grid: 12, .headMovement: 40]

    private static let sampleTimeout: TimeInterval = 5

    private static let noFaceHint: TimeInterval = 0.5

    private let tracking: TrackingController
    private let gaze: GazeService
    private let log = Log("Calibration")
    private var overlay: OverlaySet?
    private var timer: Timer?
    private var layout = ScreenLayout(displays: [])
    private var targets: [CalibrationTarget] = []
    private var samples: [CalibrationSample] = []
    private var index = 0
    private var stage = Stage.intro
    private var stageStart: TimeInterval = 0
    private var targetSamples = 0
    private var lastFace: TimeInterval = 0
    private var previousApp: NSRunningApplication?

    private(set) var isRunning = false

    var onStart: (() -> Void)?

    var onFinish: (() -> Void)?

    init(tracking: TrackingController, gaze: GazeService) {
        self.tracking = tracking
        self.gaze = gaze
    }

    func start() {
        guard !isRunning else {
            return
        }
        layout = DisplayLayoutReader.current()
        targets = CalibrationPlan.targets(for: layout)
        guard !targets.isEmpty else {
            log.error("No displays to calibrate.")
            return
        }
        onStart?()
        isRunning = true
        samples = []
        index = 0
        lastFace = 0
        previousApp = NSWorkspace.shared.frontmostApplication
        log.info("Calibration started: \(targets.count) targets on \(layout.signature).")
        let overlay = OverlaySet(interactive: true)
        overlay.onEscape = { [weak self] in
            self?.cancel()
        }
        overlay.show()
        self.overlay = overlay
        NSCursor.hide()
        enter(.intro)
        tracking.setObserver(.calibration) { [weak self] observation in
            self?.handle(observation)
        }
        tracking.acquire(.calibration)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        guard overlay != nil else {
            return
        }
        log.info("Calibration cancelled at target \(index + 1) of \(targets.count).")
        stopRecording()
        isRunning = false
    }

    private var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func enter(_ stage: Stage) {
        self.stage = stage
        stageStart = now
        targetSamples = 0
    }

    private func handle(_ observation: FaceObservation?) {
        guard let observation, let features = FeatureExtractor.extract(observation) else {
            return
        }
        lastFace = now
        guard stage == .sample, !features.isBlinking else {
            return
        }
        samples.append(
            CalibrationSample(vector: features.vector, target: index, raw: FeatureExtractor.raw(observation)))
        targetSamples += 1
    }

    private func tick() {
        guard overlay != nil, index < targets.count else {
            return
        }
        let target = targets[index]
        let elapsed = now - stageStart
        let faceVisible = now - lastFace < Self.noFaceHint
        switch stage {
        case .intro:
            if elapsed >= Self.introTime, faceVisible {
                enter(.settle)
            }
        case .settle:
            if elapsed >= CalibrationPlan.settleTime {
                enter(.sample)
            }
        case .sample:
            let duration =
                target.phase == .grid ? CalibrationPlan.gridSampleTime : CalibrationPlan.headMovementSampleTime
            let enough = targetSamples >= Self.minimumSamples[target.phase, default: 0]
            if elapsed >= duration, enough || elapsed >= duration + Self.sampleTimeout {
                if !enough {
                    log.warning("Target \(index + 1) skipped with \(targetSamples) samples.")
                }
                advance()
                return
            }
        }
        render(target, elapsed: now - stageStart, faceVisible: faceVisible)
    }

    private func render(_ target: CalibrationTarget, elapsed: TimeInterval, faceVisible: Bool) {
        var content = OverlayContent()
        content.dimmed = true
        let ring: CGFloat
        switch stage {
        case .intro:
            ring = 40
        case .settle:
            ring = 40 - 28 * CGFloat(min(elapsed / CalibrationPlan.settleTime, 1))
        case .sample:
            ring = 12
        }
        content.target = OverlayContent.Target(point: target.point, ring: ring)
        content.messageAnchor = target.point
        if stage == .intro {
            content.message = String(localized: "calibration.intro")
        } else if !faceVisible {
            content.message = String(localized: "calibration.no_face")
        } else if target.phase == .headMovement {
            content.message = String(localized: "calibration.head_movement")
        }
        overlay?.update(content)
    }

    private func advance() {
        index += 1
        if index < targets.count {
            enter(.settle)
        } else {
            finish()
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        tracking.setObserver(.calibration, nil)
        tracking.release(.calibration)
        overlay?.close()
        overlay = nil
        NSCursor.unhide()
        previousApp?.activate()
        previousApp = nil
        onFinish?()
    }

    private func finish() {
        stopRecording()
        let data = CalibrationData(
            layout: layout, targets: targets, samples: samples, cameraID: tracking.activeCameraID)
        log.info("Calibration recorded \(samples.count) samples; fitting.")
        Task {
            let model = await Task.detached { GazeModel.fit(data) }.value
            report(model)
            isRunning = false
        }
    }

    private func report(_ model: GazeModel?) {
        guard let model else {
            log.error("Calibration fit failed with \(samples.count) samples.")
            Alerts.info(String(localized: "calibration.failed.title"), String(localized: "calibration.failed.message"))
            return
        }
        do {
            try gaze.install(model)
        } catch {
            log.error("Could not save the calibration: \(error)")
            Alerts.info(String(localized: "calibration.failed.title"), String(describing: error))
            return
        }
        let lines = model.accuracy.map { accuracy in
            let name = DisplayLayoutReader.name(of: accuracy.displayID)
            log.info(
                "Accuracy \(name): \(Int(accuracy.medianMillimeters.rounded())) mm, "
                    + "\(Int(accuracy.medianPoints.rounded())) pt.")
            return String(
                localized:
                    "calibration.accuracy.line \(name) \(Int(accuracy.medianMillimeters.rounded())) \(Int(accuracy.medianPoints.rounded()))"
            )
        }
        Alerts.info(String(localized: "calibration.done.title"), lines.joined(separator: "\n"))
    }
}
