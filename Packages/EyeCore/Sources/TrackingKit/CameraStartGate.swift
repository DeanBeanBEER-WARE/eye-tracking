import Foundation

public struct CameraStartGate: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case start
        case restart
        case stop
    }

    public private(set) var isStarting = false

    public private(set) var isRunning = false

    public private(set) var isRestartPending = false

    public init() {}

    public mutating func demand() -> Action {
        guard !isStarting, !isRunning else {
            return .none
        }
        isStarting = true
        return .start
    }

    public mutating func switchCamera() -> Action {
        if isStarting {
            isRestartPending = true
            return .none
        }
        guard isRunning else {
            return .none
        }
        isRunning = false
        isStarting = true
        return .restart
    }

    public mutating func startSucceeded(hasConsumers: Bool) -> Action {
        isStarting = false
        guard hasConsumers else {
            isRestartPending = false
            return .stop
        }
        guard isRestartPending else {
            isRunning = true
            return .none
        }
        isRestartPending = false
        isStarting = true
        return .restart
    }

    public mutating func startFailed() {
        isStarting = false
        isRestartPending = false
    }

    public mutating func release() -> Action {
        isRestartPending = false
        guard isRunning else {
            return .none
        }
        isRunning = false
        return .stop
    }
}
