import Foundation
import Testing
import simd

@testable import TrackingKit

@Suite("Tracking")
struct TrackingTests {
    private static let vendor = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/mediapipe")
    private static let library = vendor.appendingPathComponent("libmediapipe.dylib").path
    private static let model = vendor.appendingPathComponent("face_landmarker.task").path
    private static let hasRuntime =
        FileManager.default.fileExists(atPath: library) && FileManager.default.fileExists(atPath: model)

    private static func rotation(_ degrees: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: degrees * .pi / 180, axis: axis))
    }

    @Test("A neutral matrix is a frontal pose with its translation as position")
    func neutralPose() {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(1, -2, -50, 1)
        let pose = HeadPose(matrix: matrix)
        #expect(abs(pose.yaw) < 1e-6 && abs(pose.pitch) < 1e-6 && abs(pose.roll) < 1e-6)
        #expect(pose.position == SIMD3(1, -2, -50))
    }

    @Test("Rotations map to yaw, pitch and roll")
    func rotations() {
        #expect(abs(HeadPose(matrix: Self.rotation(20, axis: SIMD3(0, 1, 0))).yaw - 20) < 1e-3)
        #expect(abs(HeadPose(matrix: Self.rotation(15, axis: SIMD3(1, 0, 0))).pitch - 15) < 1e-3)
        #expect(abs(HeadPose(matrix: Self.rotation(-10, axis: SIMD3(0, 0, 1))).roll + 10) < 1e-3)
    }

    @Test("Pixel positions and blendshape lookups")
    func observationHelpers() {
        let observation = FaceObservation(
            landmarks: [SIMD3(0.5, 0.25, 0)], blendshapes: ["eyeBlinkLeft": 0.75], transform: nil,
            imageWidth: 1280, imageHeight: 720, timestamp: 1)
        #expect(observation.pixel(0) == SIMD2(640, 180))
        #expect(observation.blendshape("eyeBlinkLeft") == 0.75)
        #expect(observation.blendshape("missing") == 0)
    }

    @Test(
        "MediaPipe loads, finds no face in a flat image and keeps timestamps increasing",
        .enabled(if: hasRuntime))
    func landmarker() throws {
        let landmarker = try FaceLandmarker(libraryPath: Self.library, modelPath: Self.model, caBundlePath: "")
        let pixels = [UInt8](repeating: 128, count: 320 * 240 * 3)
        for frame in 0..<3 {
            let result = try pixels.withUnsafeBufferPointer { buffer in
                try landmarker.detect(rgb: buffer.baseAddress!, width: 320, height: 240, timestamp: 1.0)
            }
            #expect(result == nil, "frame \(frame)")
        }
    }

    @Test("A missing model is a load error", .enabled(if: hasRuntime))
    func missingModel() {
        #expect(throws: FaceLandmarkerError.self) {
            try FaceLandmarker(libraryPath: Self.library, modelPath: "/nonexistent.task", caBundlePath: "")
        }
    }

    @Test("A missing library is a load error")
    func missingLibrary() {
        #expect(throws: FaceLandmarkerError.self) {
            try FaceLandmarker(libraryPath: "/nonexistent.dylib", modelPath: Self.model, caBundlePath: "")
        }
    }
}
