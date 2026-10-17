import Foundation
import simd

public struct FaceObservation: Sendable {
    public var landmarks: [SIMD3<Float>]

    public var blendshapes: [String: Float]

    public var transform: simd_float4x4?

    public var imageWidth: Int

    public var imageHeight: Int

    public var timestamp: TimeInterval

    public init(
        landmarks: [SIMD3<Float>],
        blendshapes: [String: Float],
        transform: simd_float4x4?,
        imageWidth: Int,
        imageHeight: Int,
        timestamp: TimeInterval
    ) {
        self.landmarks = landmarks
        self.blendshapes = blendshapes
        self.transform = transform
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.timestamp = timestamp
    }

    public func pixel(_ index: Int) -> SIMD2<Float> {
        let point = landmarks[index]
        return SIMD2(point.x * Float(imageWidth), point.y * Float(imageHeight))
    }

    public func blendshape(_ name: String) -> Float {
        blendshapes[name] ?? 0
    }
}
