import Foundation
import simd

/// The head orientation and position derived from the facial transformation matrix.
public struct HeadPose: Equatable, Sendable {
    /// The rotation around the vertical axis in degrees (turning left or right).
    public var yaw: Double

    /// The rotation around the horizontal axis in degrees (looking up or down).
    public var pitch: Double

    /// The rotation around the viewing axis in degrees (tilting the head).
    public var roll: Double

    /// The head position in camera space in centimeters.
    public var position: SIMD3<Double>

    /// Creates a pose.
    ///
    /// - Parameters:
    ///   - yaw: The yaw in degrees.
    ///   - pitch: The pitch in degrees.
    ///   - roll: The roll in degrees.
    ///   - position: The position in centimeters.
    public init(yaw: Double, pitch: Double, roll: Double, position: SIMD3<Double>) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.position = position
    }

    /// Derives the pose from a transformation matrix whose columns are the face axes and the face position.
    ///
    /// - Parameter matrix: The facial transformation matrix.
    public init(matrix: simd_float4x4) {
        let xAxis = SIMD3<Double>(Double(matrix.columns.0.x), Double(matrix.columns.0.y), Double(matrix.columns.0.z))
        let yAxis = SIMD3<Double>(Double(matrix.columns.1.x), Double(matrix.columns.1.y), Double(matrix.columns.1.z))
        let zAxis = SIMD3<Double>(Double(matrix.columns.2.x), Double(matrix.columns.2.y), Double(matrix.columns.2.z))
        let forward = simd_normalize(zAxis)
        let degrees = 180 / Double.pi
        yaw = atan2(forward.x, forward.z) * degrees
        pitch = asin(max(-1, min(1, -forward.y))) * degrees
        roll = atan2(xAxis.y, yAxis.y) * degrees
        position = SIMD3(Double(matrix.columns.3.x), Double(matrix.columns.3.y), Double(matrix.columns.3.z))
    }
}
