import Testing

@testable import TrackingKit

@Suite("Camera start gate")
struct CameraStartGateTests {
    @Test("The first consumer starts the camera once")
    func start() {
        var gate = CameraStartGate()
        #expect(gate.demand() == .start)
        #expect(gate.demand() == .none)
        #expect(gate.startSucceeded(hasConsumers: true) == .none)
        #expect(gate.isRunning && !gate.isStarting)
        #expect(gate.demand() == .none)
    }

    @Test("A switch while running restarts, a switch while stopped only remembers the choice")
    func switchWhileRunning() {
        var gate = CameraStartGate()
        #expect(gate.switchCamera() == .none)
        _ = gate.demand()
        _ = gate.startSucceeded(hasConsumers: true)
        #expect(gate.switchCamera() == .restart)
        #expect(gate.isStarting && !gate.isRunning)
        #expect(gate.startSucceeded(hasConsumers: true) == .none)
        #expect(gate.isRunning)
    }

    @Test("A switch during a start is queued and runs after it")
    func switchWhileStarting() {
        var gate = CameraStartGate()
        _ = gate.demand()
        #expect(gate.switchCamera() == .none)
        #expect(gate.isRestartPending)
        #expect(gate.startSucceeded(hasConsumers: true) == .restart)
        #expect(!gate.isRestartPending && gate.isStarting)
        #expect(gate.startSucceeded(hasConsumers: true) == .none)
    }

    @Test("A start that finishes without consumers stops the camera, a failure allows a new start")
    func endings() {
        var gate = CameraStartGate()
        _ = gate.demand()
        #expect(gate.release() == .none)
        #expect(gate.startSucceeded(hasConsumers: false) == .stop)
        #expect(!gate.isRunning && !gate.isStarting)
        _ = gate.demand()
        _ = gate.switchCamera()
        gate.startFailed()
        #expect(!gate.isStarting && !gate.isRestartPending)
        #expect(gate.demand() == .start)
        _ = gate.startSucceeded(hasConsumers: true)
        #expect(gate.release() == .stop)
        #expect(!gate.isRunning)
    }
}
