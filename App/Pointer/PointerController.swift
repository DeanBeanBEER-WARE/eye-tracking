import AppKit
import AppSupportKit
import CoreKit
import GazeKit
import PointerKit

/// Gaze control: moves the cursor with the gaze and takes the external mouse while the face is visible.
///
/// Buttons, wheel and tilt of the seized mouse are re-injected; its motion only drags while a button is held. The
/// trackpad is never seized: using it pauses gaze for a moment, so it serves as fine correction and as a way out.
@MainActor
final class PointerController {
    /// The points a device count of the seized mouse drags.
    private static let dragGain: CGFloat = 0.75

    /// The seconds between attempts to take a mouse the system refused.
    private static let seizeRetryInterval: TimeInterval = 3

    /// The seconds the app waits for the permissions after asking for them.
    private static let permissionWait: TimeInterval = 180

    private let gaze: GazeService
    private let settings: SettingsStore
    private let log = Log("Pointer")
    private let seizer = MouseSeizer()
    private let poster = EventPoster()
    private let monitor = ManualInputMonitor()
    private var policy = PointerPolicy()
    private var engagement = EngagementTracker()
    private var layout = DisplayLayoutReader.current()
    private var pendingMotion = CGPoint.zero
    private var flushScheduled = false
    private var permissionTimer: Timer?
    private var isPaused = false
    private var isSuspended = false
    private var nextSeizeRetry: TimeInterval = 0
    private var askedForInputMonitoring = false

    /// Whether gaze control is on.
    private(set) var isEnabled = false

    /// Creates the controller; gaze control starts with ``restore()`` or ``toggle()``.
    ///
    /// - Parameters:
    ///   - gaze: Delivers the gaze estimates.
    ///   - settings: Remembers whether gaze control is on.
    init(gaze: GazeService, settings: SettingsStore) {
        self.gaze = gaze
        self.settings = settings
        seizer.onInput = { [weak self] input in
            self?.handle(input)
        }
        seizer.onPermissionRefused = { [weak self] in
            self?.askForInputMonitoring()
        }
        monitor.onManualInput = { [weak self] in
            self?.policy.manualMovement(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    /// Switches gaze control on at launch if it was on when the app last ran.
    func restore() {
        if settings.load().gazeControl {
            enable(interactive: false)
        }
    }

    /// Switches gaze control on or off.
    func toggle() {
        if isEnabled {
            disable()
            remember(false)
        } else {
            enable(interactive: true)
        }
    }

    /// Pauses gaze control while a hotkey is held; the mouse works normally during the pause.
    ///
    /// - Parameter paused: Whether the pause starts or ends.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else {
            return
        }
        isPaused = paused
        log.info(paused ? "Paused by hotkey." : "Pause ended.")
        if paused {
            releaseMouse()
        } else {
            policy.manualMovement(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    /// Suspends gaze control while a calibration runs.
    ///
    /// - Parameter suspended: Whether the calibration starts or ended.
    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended {
            releaseMouse()
        } else {
            policy.reset()
            if !isEnabled, settings.load().gazeControl {
                enable(interactive: false)
            }
        }
    }

    /// Follows a change of the displays: stops without a matching calibration, resumes when it matches again.
    func displaysChanged() {
        layout = DisplayLayoutReader.current()
        if gaze.model == nil, isEnabled {
            log.warning("Displays changed and the calibration does not match; gaze control stops.")
            disable()
        } else if gaze.model != nil, !isEnabled, settings.load().gazeControl {
            enable(interactive: false)
        }
    }

    /// Gives the mouse back before the app quits.
    func shutDown() {
        disable()
    }

    private func enable(interactive: Bool) {
        guard !isEnabled else {
            return
        }
        guard gaze.model != nil else {
            log.info("Gaze control needs a calibration for the current displays.")
            if interactive {
                Alerts.info(
                    String(localized: "pointer.no_calibration.title"),
                    String(localized: "pointer.no_calibration.message"))
            }
            return
        }
        guard PointerPermissions.canPostEvents else {
            log.info("Accessibility permission missing.")
            if interactive {
                remember(true)
                PointerPermissions.requestPostEvents()
                Alerts.info(
                    String(localized: "pointer.permissions.title"), String(localized: "pointer.permissions.message"))
                PointerPermissions.openSettings("Privacy_Accessibility")
                waitForPermissions()
            }
            return
        }
        isEnabled = true
        remember(true)
        layout = DisplayLayoutReader.current()
        policy.reset()
        engagement.reset()
        monitor.start()
        gaze.subscribe(.pointer) { [weak self] update in
            self?.handle(update)
        }
        log.info("Gaze control on.")
    }

    private func disable() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        guard isEnabled else {
            return
        }
        isEnabled = false
        gaze.unsubscribe(.pointer)
        monitor.stop()
        releaseMouse()
        log.info("Gaze control off.")
    }

    private func remember(_ enabled: Bool) {
        do {
            try settings.update { $0.gazeControl = enabled }
        } catch {
            log.error("Could not save the gaze control state: \(error)")
        }
    }

    private func waitForPermissions() {
        permissionTimer?.invalidate()
        let deadline = ProcessInfo.processInfo.systemUptime + Self.permissionWait
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.checkPermissions(deadline: deadline)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func checkPermissions(deadline: TimeInterval) {
        if PointerPermissions.canPostEvents {
            permissionTimer?.invalidate()
            permissionTimer = nil
            log.info("Permissions granted.")
            enable(interactive: false)
        } else if ProcessInfo.processInfo.systemUptime > deadline {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    /// Asks once per run for Input Monitoring after the system refused to hand over a mouse.
    private func askForInputMonitoring() {
        guard !askedForInputMonitoring, !PointerPermissions.canListen else {
            return
        }
        askedForInputMonitoring = true
        log.info("Asking for Input Monitoring.")
        PointerPermissions.requestListen()
    }

    private func handle(_ update: GazeUpdate) {
        let now = ProcessInfo.processInfo.systemUptime
        let faceVisible: Bool
        switch update {
        case .estimate, .blink:
            faceVisible = true
        case .noFace:
            faceVisible = false
        }
        let engaged = engagement.update(faceVisible: faceVisible, now: now)
        let active = engaged && !isPaused && !isSuspended
        if active, !seizer.isEngaged {
            seizer.engage()
            log.info("Face found; gaze controls the pointer.")
        } else if active, seizer.hasRefusedDevices, now >= nextSeizeRetry {
            nextSeizeRetry = now + Self.seizeRetryInterval
            seizer.retry()
        } else if !active, seizer.isEngaged {
            releaseMouse()
            if !engaged {
                log.info("Face lost; the mouse works normally.")
            }
        }
        guard active, case .estimate(let estimate) = update else {
            return
        }
        let millimetersPerPoint = layout.display(id: estimate.displayID)?.millimetersPerPoint ?? 0.25
        if let target = policy.target(for: estimate, millimetersPerPoint: millimetersPerPoint, now: now) {
            poster.move(to: target)
        }
    }

    private func handle(_ input: MouseInput) {
        let now = ProcessInfo.processInfo.systemUptime
        switch input {
        case .button(let number, let isDown):
            flushMotion()
            policy.button(number, isDown: isDown, now: now)
            poster.button(number, isDown: isDown)
        case .wheel(let notches):
            poster.scroll(wheel: notches, pan: 0)
        case .pan(let notches):
            poster.scroll(wheel: 0, pan: notches)
        case .motionX(let counts):
            pendingMotion.x += CGFloat(counts)
            scheduleFlush()
        case .motionY(let counts):
            pendingMotion.y += CGFloat(counts)
            scheduleFlush()
        }
    }

    /// Collects the X and Y values of one report into one drag event.
    private func scheduleFlush() {
        guard !flushScheduled else {
            return
        }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.flushMotion()
            }
        }
    }

    private func flushMotion() {
        flushScheduled = false
        let motion = pendingMotion
        pendingMotion = .zero
        guard motion != .zero, poster.isButtonHeld else {
            return
        }
        let layout = layout
        poster.drag(by: CGPoint(x: motion.x * Self.dragGain, y: motion.y * Self.dragGain)) { layout.clamp($0) }
    }

    private func releaseMouse() {
        flushMotion()
        poster.releaseAll()
        seizer.release()
        policy.reset()
        engagement.reset()
    }
}
