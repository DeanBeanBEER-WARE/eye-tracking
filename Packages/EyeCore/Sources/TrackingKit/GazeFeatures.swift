import Foundation
import simd

public struct EyeMeasurement: Equatable, Sendable {
    public var horizontal: Double

    public var vertical: Double

    public var openness: Double

    public var width: Double

    public init(horizontal: Double, vertical: Double, openness: Double, width: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.openness = openness
        self.width = width
    }
}

public struct GazeFeatures: Equatable, Sendable {
    public static let vectorLength = 14

    public static let vectorVersion = 2

    public var imageLeftEye: EyeMeasurement

    public var imageRightEye: EyeMeasurement

    public var pose: HeadPose

    public var blendshapeHorizontal: Double

    public var blendshapeVertical: Double

    public var blink: Double

    public var timestamp: TimeInterval

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

    public var isBlinking: Bool {
        blink > 0.5
    }

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

    public var iris: SIMD2<Double> {
        let weights = eyeWeights
        return SIMD2(
            imageLeftEye.horizontal * weights.left + imageRightEye.horizontal * weights.right,
            imageLeftEye.vertical * weights.left + imageRightEye.vertical * weights.right
        )
    }

    public var vector: [Double] {
        [
            imageLeftEye.horizontal, imageRightEye.horizontal, imageLeftEye.vertical, imageRightEye.vertical,
            blendshapeHorizontal, blendshapeVertical, pose.yaw, pose.pitch, pose.roll,
            pose.position.x, pose.position.y, pose.position.z, imageLeftEye.openness, imageRightEye.openness,
        ]
    }
}

public enum FeatureExtractor {
    struct EyeIndices {
        let leftCorner: Int
        let rightCorner: Int
        let upperLid: Int
        let lowerLid: Int
        let iris: Int
    }

    static let imageLeftEye = EyeIndices(leftCorner: 33, rightCorner: 133, upperLid: 159, lowerLid: 145, iris: 468)

    static let imageRightEye = EyeIndices(leftCorner: 362, rightCorner: 263, upperLid: 386, lowerLid: 374, iris: 473)

    public static func extract(_ observation: FaceObservation) -> GazeFeatures? {
        guard let transform = observation.transform, observation.landmarks.count > 473,
            let left = measure(observation, imageLeftEye), let right = measure(observation, imageRightEye)
        else {
            return nil
        }
        let shape = { (name: String) in Double(observation.blendshape(name)) }
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
            blink: min(shape("eyeBlinkLeft"), shape("eyeBlinkRight")),
            timestamp: observation.timestamp
        )
    }

    public static let recordedLandmarks = [
        33, 133, 159, 145, 468, 469, 470, 471, 472, 362, 263, 386, 374, 473, 474, 475, 476, 477,
    ]

    public static let recordedBlendshapes = [
        "eyeLookInLeft", "eyeLookOutLeft", "eyeLookUpLeft", "eyeLookDownLeft", "eyeLookInRight", "eyeLookOutRight",
        "eyeLookUpRight", "eyeLookDownRight", "eyeBlinkLeft", "eyeBlinkRight",
    ]

    public static func raw(_ observation: FaceObservation) -> [Float] {
        guard observation.landmarks.count > 477 else {
            return []
        }
        var values: [Float] = []
        values.reserveCapacity(recordedLandmarks.count * 3 + 16 + recordedBlendshapes.count)
        for index in recordedLandmarks {
            let pixel = observation.pixel(index)
            values += [pixel.x, pixel.y, observation.landmarks[index].z]
        }
        let matrix = observation.transform ?? simd_float4x4()
        for column in 0..<4 {
            values += [matrix[column].x, matrix[column].y, matrix[column].z, matrix[column].w]
        }
        values += recordedBlendshapes.map { observation.blendshape($0) }
        return values
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
        return EyeMeasurement(
            horizontal: simd_dot(iris - center, along) / width,
            vertical: simd_dot(iris - center, across) / width,
            openness: simd_length(upper - lower) / width,
            width: width
        )
    }
}
