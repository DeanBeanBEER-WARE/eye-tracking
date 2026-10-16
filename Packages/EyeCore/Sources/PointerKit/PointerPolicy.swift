import CoreGraphics
import Foundation
import GazeKit

/// The tuning of the gaze pointer.
public struct PointerConfiguration: Equatable, Sendable {
    /// The gaze must move this many degrees away from where it rested before the cursor follows.
    public var deadZoneDegrees: Double

    /// Below this gaze speed in degrees per second the gaze counts as resting.
    public var settleSpeed: Double

    /// The seconds the gaze must rest before the cursor stops following.
    public var settleDuration: TimeInterval

    /// The seconds the cursor stays still after a mouse button was released, so double clicks land on one spot.
    public var releaseHold: TimeInterval

    /// The seconds gaze stays paused after the trackpad or another unseized device moved the cursor.
    public var manualPause: TimeInterval

    /// The assumed viewing distance in millimeters.
    public var viewingDistance: Double

    /// The default tuning.
    public static let standard = PointerConfiguration(
        deadZoneDegrees: 2.0, settleSpeed: 8, settleDuration: 0.12, releaseHold: 0.35, manualPause: 1.2,
        viewingDistance: GazeEstimator.viewingDistance)

    /// Creates a tuning.
    ///
    /// - Parameters:
    ///   - deadZoneDegrees: The dead zone in degrees.
    ///   - settleSpeed: The resting speed in degrees per second.
    ///   - settleDuration: The resting time in seconds.
    ///   - releaseHold: The stillness after a button release in seconds.
    ///   - manualPause: The pause after manual pointer movement in seconds.
    ///   - viewingDistance: The viewing distance in millimeters.
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

/// Decides when the cursor follows the gaze.
///
/// The cursor rests while the gaze rests and while a mouse button is held. When the gaze leaves the spot where it
/// rested by more than the dead zone (a saccade), the cursor follows the smoothed gaze until the gaze rests again.
/// The dead zone is measured in gaze space, so a cursor corrected by hand (trackpad) is not pulled back to the
/// slightly wrong gaze estimate.
public struct PointerPolicy: Sendable {
    /// The tuning.
    public var configuration: PointerConfiguration

    private var following = false
    private var anchor: CGPoint?
    private var restingSince: TimeInterval?
    private var heldButtons: Set<Int> = []
    private var stillUntil: TimeInterval = 0
    private var reanchor = false

    /// Creates a policy; the first estimate moves the cursor.
    ///
    /// - Parameter configuration: The tuning.
    public init(configuration: PointerConfiguration = .standard) {
        self.configuration = configuration
    }

    /// Whether a mouse button is held.
    public var isButtonHeld: Bool {
        !heldButtons.isEmpty
    }

    /// Whether the cursor currently follows the gaze.
    public var isFollowing: Bool {
        following
    }

    /// Decides the cursor position for a new gaze estimate.
    ///
    /// - Parameters:
    ///   - estimate: The smoothed gaze estimate.
    ///   - millimetersPerPoint: The size of a point on the display of the estimate.
    ///   - now: The current time in seconds.
    /// - Returns: The new cursor position, or `nil` if the cursor stays.
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
        following = true
        restingSince = nil
        return follow(estimate, now: now)
    }

    /// Records a mouse button change of the seized mouse.
    ///
    /// - Parameters:
    ///   - button: The button number.
    ///   - isDown: Whether the button went down.
    ///   - now: The current time in seconds.
    public mutating func button(_ button: Int, isDown: Bool, now: TimeInterval) {
        if isDown {
            heldButtons.insert(button)
        } else {
            heldButtons.remove(button)
            stillUntil = max(stillUntil, now + configuration.releaseHold)
        }
        following = false
        reanchor = true
    }

    /// Records that another device (the trackpad) moved the cursor; gaze pauses for a moment.
    ///
    /// - Parameter now: The current time in seconds.
    public mutating func manualMovement(now: TimeInterval) {
        stillUntil = max(stillUntil, now + configuration.manualPause)
        following = false
        reanchor = true
    }

    /// Forgets all state, for example after gaze control was off; the next estimate moves the cursor.
    public mutating func reset() {
        following = false
        anchor = nil
        restingSince = nil
        heldButtons = []
        stillUntil = 0
        reanchor = false
    }

    private mutating func follow(_ estimate: GazeEstimate, now: TimeInterval) -> CGPoint {
        following = true
        if estimate.speed < configuration.settleSpeed {
            let since = restingSince ?? now
            restingSince = since
            if now - since >= configuration.settleDuration {
                following = false
                anchor = estimate.point
            }
        } else {
            restingSince = nil
        }
        return estimate.point
    }
}

/// Decides whether gaze control holds the mouse, with hysteresis against short face losses.
public struct EngagementTracker: Sendable {
    /// The seconds without a face after which the mouse is released.
    public var releaseAfter: TimeInterval

    /// The seconds the face must be visible before the mouse is taken again.
    public var engageAfter: TimeInterval

    private var lastFace: TimeInterval?
    private var faceSince: TimeInterval?
    /// Whether gaze control holds the mouse.
    public private(set) var isEngaged = false

    /// Creates a tracker that starts released.
    ///
    /// - Parameters:
    ///   - releaseAfter: The face loss time in seconds.
    ///   - engageAfter: The face presence time in seconds.
    public init(releaseAfter: TimeInterval = 1.0, engageAfter: TimeInterval = 0.4) {
        self.releaseAfter = releaseAfter
        self.engageAfter = engageAfter
    }

    /// Updates the state with one camera frame.
    ///
    /// - Parameters:
    ///   - faceVisible: Whether the frame shows a face (a blink counts as visible).
    ///   - now: The current time in seconds.
    /// - Returns: Whether gaze control should hold the mouse.
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

    /// Releases and forgets the face history.
    public mutating func reset() {
        lastFace = nil
        faceSince = nil
        isEngaged = false
    }
}
