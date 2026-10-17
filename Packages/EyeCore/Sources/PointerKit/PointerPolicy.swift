import CoreGraphics
import Foundation
import GazeKit

public struct PointerConfiguration: Equatable, Sendable {
    public var deadZoneDegrees: Double

    public var settleSpeed: Double

    public var settleDuration: TimeInterval

    public var releaseHold: TimeInterval

    public var manualPause: TimeInterval

    public var viewingDistance: Double

    public static let standard = PointerConfiguration(
        deadZoneDegrees: 2.0, settleSpeed: 8, settleDuration: 0.12, releaseHold: 0.35, manualPause: 1.2,
        viewingDistance: GazeEstimator.viewingDistance)

    public init(
        deadZoneDegrees: Double, settleSpeed: Double, settleDuration: TimeInterval, releaseHold: TimeInterval,
        manualPause: TimeInterval, viewingDistance: Double
    ) {
        self.deadZoneDegrees = deadZoneDegrees
        self.settleSpeed = settleSpeed
        self.settleDuration = settleDuration
        self.releaseHold = releaseHold
        self.manualPause = manualPause
        self.viewingDistance = viewingDistance
    }
}

public struct PointerPolicy: Sendable {
    public var configuration: PointerConfiguration

    private var following = false
    private var anchor: CGPoint?
    private var restingSince: TimeInterval?
    private var heldButtons: Set<Int> = []
    private var stillUntil: TimeInterval = 0
    private var reanchor = false

    public private(set) var epoch = 0

    public private(set) var landing: CGPoint?

    public init(configuration: PointerConfiguration = .standard) {
        self.configuration = configuration
    }

    public var isButtonHeld: Bool {
        !heldButtons.isEmpty
    }

    public var isFollowing: Bool {
        following
    }

    public mutating func target(
        for estimate: GazeEstimate, millimetersPerPoint: Double, now: TimeInterval
    ) -> CGPoint? {
        if isButtonHeld || now < stillUntil {
            following = false
            restingSince = nil
            reanchor = true
            return nil
        }
        if reanchor {
            reanchor = false
            anchor = estimate.point
            return nil
        }
        guard let anchor, !following else {
            return follow(estimate, now: now)
        }
        let millimeters = hypot(estimate.point.x - anchor.x, estimate.point.y - anchor.y) * millimetersPerPoint
        let degrees = atan(millimeters / configuration.viewingDistance) * 180 / .pi
        guard degrees > configuration.deadZoneDegrees else {
            return nil
        }
        restingSince = nil
        return follow(estimate, now: now)
    }

    public mutating func button(_ button: Int, isDown: Bool, now: TimeInterval) {
        if isDown {
            heldButtons.insert(button)
        } else {
            heldButtons.remove(button)
            stillUntil = max(stillUntil, now + configuration.releaseHold)
        }
        interrupt()
    }

    public mutating func manualMovement(now: TimeInterval) {
        stillUntil = max(stillUntil, now + configuration.manualPause)
        interrupt()
    }

    public mutating func reset() {
        following = false
        anchor = nil
        restingSince = nil
        heldButtons = []
        stillUntil = 0
        reanchor = false
        landing = nil
        epoch += 1
    }

    private mutating func interrupt() {
        following = false
        reanchor = true
        landing = nil
        epoch += 1
    }

    private mutating func follow(_ estimate: GazeEstimate, now: TimeInterval) -> CGPoint {
        if !following {
            following = true
            landing = nil
            epoch += 1
        }
        if estimate.speed < configuration.settleSpeed {
            let since = restingSince ?? now
            restingSince = since
            if now - since >= configuration.settleDuration {
                following = false
                anchor = estimate.point
                landing = estimate.point
                epoch += 1
            }
        } else {
            restingSince = nil
        }
        return estimate.point
    }
}

public struct EngagementTracker: Sendable {
    public var releaseAfter: TimeInterval

    public var engageAfter: TimeInterval

    private var lastFace: TimeInterval?
    private var faceSince: TimeInterval?
    public private(set) var isEngaged = false

    public init(releaseAfter: TimeInterval = 1.0, engageAfter: TimeInterval = 0.4) {
        self.releaseAfter = releaseAfter
        self.engageAfter = engageAfter
    }

    public mutating func update(faceVisible: Bool, now: TimeInterval) -> Bool {
        if faceVisible {
            lastFace = now
            let since = faceSince ?? now
            faceSince = since
            if !isEngaged, now - since >= engageAfter {
                isEngaged = true
            }
        } else {
            faceSince = nil
            if isEngaged, now - (lastFace ?? now) >= releaseAfter {
                isEngaged = false
            }
        }
        return isEngaged
    }

    public mutating func reset() {
        lastFace = nil
        faceSince = nil
        isEngaged = false
    }
}
