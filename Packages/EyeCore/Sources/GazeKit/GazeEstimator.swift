import CoreGraphics
import Foundation
import TrackingKit

public struct GazeEstimate: Equatable, Sendable {
    public var point: CGPoint

    public var displayID: UInt32

    public var speed: Double

    public var timestamp: TimeInterval

    public init(point: CGPoint, displayID: UInt32, speed: Double, timestamp: TimeInterval) {
        self.point = point
        self.displayID = displayID
        self.speed = speed
        self.timestamp = timestamp
    }
}

public struct GazeEstimator: Sendable {
    public static let viewingDistance: Double = 650

    public let model: GazeModel

    private var filterX = OneEuroFilter(minimumCutoff: 0.6, beta: 0.004)
    private var filterY = OneEuroFilter(minimumCutoff: 0.6, beta: 0.004)
    private var last: GazeEstimate?

    public init(model: GazeModel) {
        self.model = model
    }

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

    public mutating func reset() {
        filterX.reset()
        filterY.reset()
        last = nil
    }
}
