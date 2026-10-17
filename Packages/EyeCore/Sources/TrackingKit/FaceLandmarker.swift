import CMediaPipe
import Foundation
import simd

public enum FaceLandmarkerError: Error, Equatable, Sendable, CustomStringConvertible {
    case loadFailed(String)

    case detectionFailed(String)

    public var description: String {
        switch self {
        case .loadFailed(let message): "MediaPipe could not be loaded: \(message)"
        case .detectionFailed(let message): "face detection failed: \(message)"
        }
    }
}

public final class FaceLandmarker: @unchecked Sendable {
    private static let errorLength = 512

    private let tracker: OpaquePointer
    private var lastTimestamp: Int64 = -1

    public init(libraryPath: String, modelPath: String, caBundlePath: String) throws(FaceLandmarkerError) {
        var error = [CChar](repeating: 0, count: Self.errorLength)
        guard
            let tracker = cmp_face_tracker_create(
                libraryPath, modelPath, caBundlePath, &error, Int32(Self.errorLength))
        else {
            throw .loadFailed(Self.message(error))
        }
        self.tracker = tracker
    }

    deinit {
        cmp_face_tracker_destroy(tracker)
    }

    public func detect(rgb: UnsafePointer<UInt8>, width: Int, height: Int, timestamp: TimeInterval)
        throws(FaceLandmarkerError) -> FaceObservation?
    {
        let milliseconds = max(lastTimestamp + 1, Int64((timestamp * 1000).rounded()))
        lastTimestamp = milliseconds
        var error = [CChar](repeating: 0, count: Self.errorLength)
        let found = cmp_face_tracker_detect(
            tracker, rgb, Int32(width), Int32(height), milliseconds, &error, Int32(Self.errorLength))
        guard found >= 0 else {
            throw .detectionFailed(Self.message(error))
        }
        guard found == 1 else {
            return nil
        }
        return FaceObservation(
            landmarks: landmarks(),
            blendshapes: blendshapes(),
            transform: transform(),
            imageWidth: width,
            imageHeight: height,
            timestamp: timestamp
        )
    }

    private static func message(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func landmarks() -> [SIMD3<Float>] {
        let count = Int(CMP_LANDMARK_COUNT)
        let values = UnsafeBufferPointer(start: cmp_face_tracker_landmarks(tracker), count: count * 3)
        return (0..<count).map { SIMD3(values[$0 * 3], values[$0 * 3 + 1], values[$0 * 3 + 2]) }
    }

    private func blendshapes() -> [String: Float] {
        let count = Int(cmp_face_tracker_blendshape_count(tracker))
        guard count > 0, let scores = cmp_face_tracker_blendshape_scores(tracker) else {
            return [:]
        }
        var result: [String: Float] = [:]
        for index in 0..<count {
            let name = String(cString: cmp_face_tracker_blendshape_name(tracker, Int32(index)))
            if !name.isEmpty {
                result[name] = scores[index]
            }
        }
        return result
    }

    private func transform() -> simd_float4x4? {
        guard cmp_face_tracker_has_matrix(tracker) == 1, let values = cmp_face_tracker_matrix(tracker) else {
            return nil
        }
        return simd_float4x4(
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        )
    }
}
