import Foundation
import simd

/// One face found in a camera frame.
public struct FaceObservation: Sendable {
    /// The 478 landmarks: x and y normalized to the image (origin top left), z the relative depth.
    public var landmarks: [SIMD3<Float>]

    /// The blendshape scores by category name, for example `eyeBlinkLeft`.
    public var blendshapes: [String: Float]

    /// The facial transformation matrix from the canonical face model to camera space (centimeters), if any.
    public var transform: simd_float4x4?

    /// The image width in pixels.
    public var imageWidth: Int

    /// The image height in pixels.
    public var imageHeight: Int

    /// The capture time in seconds of the host clock.
    public var timestamp: TimeInterval

    /// Creates an observation.
    ///
    /// - Parameters:
    ///   - landmarks: The normalized landmarks.
    ///   - blendshapes: The blendshape scores by name.
    ///   - transform: The facial transformation matrix, if any.
    ///   - imageWidth: The image width in pixels.
    ///   - imageHeight: The image height in pixels.
    ///   - timestamp: The capture time in seconds.
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

    /// A landmark in pixel coordinates, so that distances are not distorted by the aspect ratio.
    ///
    /// - Parameter index: The landmark index.
    /// - Returns: The x and y position in pixels.
    public func pixel(_ index: Int) -> SIMD2<Float> {
        let point = landmarks[index]
        return SIMD2(point.x * Float(imageWidth), point.y * Float(imageHeight))
    }

    /// A blendshape score.
    ///
    /// - Parameter name: The category name, for example `eyeBlinkLeft`.
    /// - Returns: The score, or 0 if the category is missing.
    public func blendshape(_ name: String) -> Float {
        blendshapes[name] ?? 0
    }
}
