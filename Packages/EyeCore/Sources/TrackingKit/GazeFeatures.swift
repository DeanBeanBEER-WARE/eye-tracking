import Foundation
import simd

/// The iris position inside one eye, measured in the camera image.
public struct EyeMeasurement: Equatable, Sendable {
    /// The iris offset along the eye axis, in eye widths; positive towards the right side of the image.
    public var horizontal: Double

    /// The iris offset across the eye axis from the lid midpoint, in eye widths; positive towards the bottom
    /// of the image.
    public var vertical: Double

    /// The lid opening in eye widths.
    public var openness: Double

    /// The eye width in pixels; it shrinks for the eye that turns away from the camera.
    public var width: Double

    /// Creates a measurement.
    ///
    /// - Parameters:
    ///   - horizontal: The iris offset along the eye axis in eye widths.
    ///   - vertical: The iris offset across the eye axis in eye widths.
    ///   - openness: The lid opening in eye widths.
    ///   - width: The eye width in pixels.
    public init(horizontal: Double, vertical: Double, openness: Double, width: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.openness = openness
        self.width = width
    }
}

/// The gaze-relevant measurements of one camera frame.
public struct GazeFeatures: Equatable, Sendable {
    /// The number of values in ``vector``.
    public static let vectorLength = 11

    /// The eye that appears on the left side of the camera image (the subject's right eye).
    public var imageLeftEye: EyeMeasurement

    /// The eye that appears on the right side of the camera image (the subject's left eye).
    public var imageRightEye: EyeMeasurement

    /// The head pose.
    public var pose: HeadPose

    /// The horizontal gaze from the blendshapes, positive towards the right side of the image.
    public var blendshapeHorizontal: Double

    /// The vertical gaze from the blendshapes, positive upwards.
    public var blendshapeVertical: Double

    /// The larger of the two blink scores.
    public var blink: Double

    /// The capture time in seconds.
    public var timestamp: TimeInterval

    /// Creates features.
    ///
    /// - Parameters:
    ///   - imageLeftEye: The eye on the left side of the image.
    ///   - imageRightEye: The eye on the right side of the image.
    ///   - pose: The head pose.
    ///   - blendshapeHorizontal: The horizontal blendshape gaze.
    ///   - blendshapeVertical: The vertical blendshape gaze.
    ///   - blink: The larger blink score.
    ///   - timestamp: The capture time in seconds.
    public init(
        imageLeftEye: EyeMeasurement,
        imageRightEye: EyeMeasurement,
        pose: HeadPose,
        blendshapeHorizontal: Double,
        blendshapeVertical: Double,
        blink: Double,
        timestamp: TimeInterval
    ) {
        self.imageLeftEye = imageLeftEye
        self.imageRightEye = imageRightEye
        self.pose = pose
        self.blendshapeHorizontal = blendshapeHorizontal
        self.blendshapeVertical = blendshapeVertical
        self.blink = blink
        self.timestamp = timestamp
    }

    /// Whether the eyes are closed too far for a gaze measurement.
    public var isBlinking: Bool {
        blink > 0.5
    }

    /// The weights of the image-left and image-right eye: the eye turned away from the camera looks narrower and
    /// a nearly closed eye is unreliable, so both count less.
    public var eyeWeights: (left: Double, right: Double) {
        func weight(_ eye: EyeMeasurement) -> Double {
            eye.width * min(1, max(0.05, eye.openness / 0.25))
        }
        let left = weight(imageLeftEye)
        let right = weight(imageRightEye)
        let total = left + right
        guard total > 0 else {
            return (0.5, 0.5)
        }
        return (left / total, right / total)
    }

    /// The weighted iris offsets of both eyes.
    public var iris: SIMD2<Double> {
        let weights = eyeWeights
        return SIMD2(
            imageLeftEye.horizontal * weights.left + imageRightEye.horizontal * weights.right,
            imageLeftEye.vertical * weights.left + imageRightEye.vertical * weights.right
        )
    }

    /// The values the gaze model is fitted on, in a fixed order: iris x and y, blendshape x and y, yaw, pitch,
    /// roll in degrees, head position x, y, z in centimeters, mean lid opening.
    public var vector: [Double] {
        let iris = iris
        return [
            iris.x, iris.y, blendshapeHorizontal, blendshapeVertical, pose.yaw, pose.pitch, pose.roll,
            pose.position.x, pose.position.y, pose.position.z,
            (imageLeftEye.openness + imageRightEye.openness) / 2,
        ]
    }
}

/// Derives ``GazeFeatures`` from the MediaPipe landmarks.
public enum FeatureExtractor {
    /// Landmark indices of one eye: the corner on the image-left side, the corner on the image-right side, the
    /// upper and lower lid and the iris center.
    struct EyeIndices {
        let leftCorner: Int
        let rightCorner: Int
        let upperLid: Int
        let lowerLid: Int
        let iris: Int
    }

    /// The subject's right eye (image-left in the unmirrored camera image): outer corner 33, inner corner 133.
    static let imageLeftEye = EyeIndices(leftCorner: 33, rightCorner: 133, upperLid: 159, lowerLid: 145, iris: 468)

    /// The subject's left eye (image-right): inner corner 362, outer corner 263.
    static let imageRightEye = EyeIndices(leftCorner: 362, rightCorner: 263, upperLid: 386, lowerLid: 374, iris: 473)

    /// Extracts the features of a face.
    ///
    /// - Parameter observation: The face.
    /// - Returns: The features, or `nil` if the face has no transformation matrix or degenerate eyes.
    public static func extract(_ observation: FaceObservation) -> GazeFeatures? {
        guard let transform = observation.transform, observation.landmarks.count > 473,
            let left = measure(observation, imageLeftEye), let right = measure(observation, imageRightEye)
        else {
            return nil
        }
        let shape = { (name: String) in Double(observation.blendshape(name)) }
        // MediaPipe names the eyes from the subject's view: the subject's left eye is on the image-right side,
        // looking "out" with it means looking towards the image-right side.
        let horizontal =
            (shape("eyeLookOutLeft") + shape("eyeLookInRight") - shape("eyeLookInLeft") - shape("eyeLookOutRight")) / 2
        let vertical =
            (shape("eyeLookUpLeft") + shape("eyeLookUpRight") - shape("eyeLookDownLeft") - shape("eyeLookDownRight"))
            / 2
        return GazeFeatures(
            imageLeftEye: left,
            imageRightEye: right,
            pose: HeadPose(matrix: transform),
            blendshapeHorizontal: horizontal,
            blendshapeVertical: vertical,
            blink: max(shape("eyeBlinkLeft"), shape("eyeBlinkRight")),
            timestamp: observation.timestamp
        )
    }

    static func measure(_ observation: FaceObservation, _ eye: EyeIndices) -> EyeMeasurement? {
        let left = SIMD2<Double>(observation.pixel(eye.leftCorner))
        let right = SIMD2<Double>(observation.pixel(eye.rightCorner))
        let axis = right - left
        let width = simd_length(axis)
        guard width > 1 else {
            return nil
        }
        let along = axis / width
        let across = SIMD2(-along.y, along.x)
        let upper = SIMD2<Double>(observation.pixel(eye.upperLid))
        let lower = SIMD2<Double>(observation.pixel(eye.lowerLid))
        let iris = SIMD2<Double>(observation.pixel(eye.iris))
        let center = (left + right) / 2
        let lidMid = (upper + lower) / 2
        return EyeMeasurement(
            horizontal: simd_dot(iris - center, along) / width,
            vertical: simd_dot(iris - lidMid, across) / width,
            openness: simd_length(upper - lower) / width,
            width: width
        )
    }
}
