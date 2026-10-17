import Foundation
import simd

public struct HeadPose: Equatable, Sendable {
    public var yaw: Double

    public var pitch: Double

    public var roll: Double

    public var position: SIMD3<Double>

    public init(yaw: Double, pitch: Double, roll: Double, position: SIMD3<Double>) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.position = position
    }

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
