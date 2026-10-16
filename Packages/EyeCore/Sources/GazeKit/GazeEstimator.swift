import CoreGraphics
import Foundation
import TrackingKit

/// A smoothed gaze point.
public struct GazeEstimate: Equatable, Sendable {
    /// The gaze point in global points.
    public var point: CGPoint

    /// The display the gaze is on.
    public var displayID: UInt32

    /// The angular speed of the smoothed gaze in degrees per second.
    public var speed: Double

    /// The capture time of the frame in seconds.
    public var timestamp: TimeInterval

    /// Creates an estimate.
    ///
    /// - Parameters:
    ///   - point: The gaze point.
    ///   - displayID: The display.
    ///   - speed: The angular speed in degrees per second.
    ///   - timestamp: The capture time.
    public init(point: CGPoint, displayID: UInt32, speed: Double, timestamp: TimeInterval) {
        self.point = point
        self.displayID = displayID
        self.speed = speed
        self.timestamp = timestamp
    }
}

/// Turns gaze features into smoothed gaze points with the calibrated model.
public struct GazeEstimator: Sendable {
    /// The assumed viewing distance in millimeters, used to express speeds as angles.
    public static let viewingDistance: Double = 650

    /// The model.
    public let model: GazeModel

    private var filterX = OneEuroFilter(minimumCutoff: 0.6, beta: 0.004)
    private var filterY = OneEuroFilter(minimumCutoff: 0.6, beta: 0.004)
    private var last: GazeEstimate?

    /// Creates an estimator.
    ///
    /// - Parameter model: The calibrated model.
    public init(model: GazeModel) {
        self.model = model
    }

    /// Estimates the gaze of one frame.
    ///
    /// - Parameter features: The features of the frame.
    /// - Returns: The smoothed estimate, or `nil` while the eyes are closed.
    public mutating func update(_ features: GazeFeatures) -> GazeEstimate? {
        guard !features.isBlinking, let raw = model.predict(features.vector) else {
            return nil
        }
        let time = features.timestamp
        let smoothed = CGPoint(
            x: filterX.filter(Double(raw.point.x), at: time), y: filterY.filter(Double(raw.point.y), at: time))
        let point = model.layout.clamp(smoothed)
        let display = model.layout.display(near: point)
        var speed = 0.0
        if let last, time > last.timestamp, let display {
            let millimeters = hypot(point.x - last.point.x, point.y - last.point.y) * display.millimetersPerPoint
            speed = atan(millimeters / Self.viewingDistance) * 180 / .pi / (time - last.timestamp)
        }
        let estimate = GazeEstimate(
            point: point, displayID: display?.id ?? raw.displayID, speed: speed, timestamp: time)
        last = estimate
        return estimate
    }

    /// Forgets the smoothing history, for example after the face was lost.
    public mutating func reset() {
        filterX.reset()
        filterY.reset()
        last = nil
    }
}
