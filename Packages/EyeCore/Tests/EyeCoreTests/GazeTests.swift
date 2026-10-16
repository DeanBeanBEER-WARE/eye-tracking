import CoreGraphics
import Foundation
import Testing
import simd

@testable import GazeKit
@testable import TrackingKit

@Suite("Gaze")
struct GazeTests {
    static let lower = DisplayInfo(
        id: 2, frame: CGRect(x: 0, y: 0, width: 3440, height: 1440), physicalSize: CGSize(width: 801, height: 329),
        isBuiltIn: false)
    static let upper = DisplayInfo(
        id: 12, frame: CGRect(x: 0, y: -1440, width: 3440, height: 1440),
        physicalSize: CGSize(width: 801, height: 335), isBuiltIn: false)
    static let builtIn = DisplayInfo(
        id: 1, frame: CGRect(x: -1512, y: -440, width: 1512, height: 982),
        physicalSize: CGSize(width: 301, height: 195), isBuiltIn: true)
    static let layout = ScreenLayout(displays: [lower, upper, builtIn])

    /// Features whose iris offsets encode the global target point, as an idealized camera would see them.
    static func features(for point: CGPoint, noise: Double = 0, time: TimeInterval = 0) -> GazeFeatures {
        let x = Double(point.x) / 4000 + noise
        let y = Double(point.y) / 3000 - noise
        let eye = EyeMeasurement(horizontal: x, vertical: y, openness: 0.3, width: 40)
        return GazeFeatures(
            imageLeftEye: eye, imageRightEye: eye,
            pose: HeadPose(yaw: x * 20, pitch: y * 15, roll: 0, position: SIMD3(0, 0, -60)),
            blendshapeHorizontal: x / 2, blendshapeVertical: -y / 2, blink: 0, timestamp: time)
    }

    static func calibration() -> CalibrationData {
        let targets = CalibrationPlan.targets(for: layout)
        var samples: [CalibrationSample] = []
        for (index, target) in targets.enumerated() {
            for step in 0..<12 {
                let noise = Double(step % 4 - 2) * 0.002
                samples.append(
                    CalibrationSample(vector: features(for: target.point, noise: noise).vector, target: index))
            }
        }
        return CalibrationData(layout: layout, targets: targets, samples: samples)
    }

    @Test("Ridge regression recovers a linear function and leaves the bias unpenalized")
    func ridge() throws {
        let rows = (0..<20).map { index -> [Double] in [1, Double(index), Double(index % 3)] }
        let targets = rows.map { 2 + 3 * $0[1] - $0[2] }
        let weights = try #require(RidgeRegression.fit(rows: rows, targets: targets, lambda: 1e-9))
        #expect(abs(weights[0] - 2) < 1e-6 && abs(weights[1] - 3) < 1e-6 && abs(weights[2] + 1) < 1e-6)
        #expect(RidgeRegression.fit(rows: [], targets: [], lambda: 1) == nil)
        let solution = try #require(RidgeRegression.solveSymmetricPositiveDefinite([4, 2, 2, 3], [2, 1], size: 2))
        #expect(abs(solution[0] - 0.5) < 1e-12 && abs(solution[1]) < 1e-12)
    }

    @Test("The plan visits the built-in display first, grids in snake order, head movement last")
    func plan() {
        let targets = CalibrationPlan.targets(for: Self.layout)
        #expect(targets.count == 6 + 9 + 9 + 3)
        #expect(targets.prefix(6).allSatisfy { $0.displayID == 1 && $0.phase == .grid })
        #expect(targets[6].displayID == 2 && targets[15].displayID == 12)
        #expect(
            targets[0].normalized == CGPoint(x: 0.08, y: 0.15) && targets[3].normalized == CGPoint(x: 0.92, y: 0.85))
        #expect(targets.suffix(3).allSatisfy { $0.phase == .headMovement && $0.normalized == CGPoint(x: 0.5, y: 0.5) })
        #expect(targets[6].point == CGPoint(x: 0.08 * 3440, y: 0.1 * 1440))
    }

    @Test("Layout lookups, clamping and the signature")
    func layoutHelpers() {
        let layout = Self.layout
        #expect(layout.display(near: CGPoint(x: 100, y: -100))?.id == 12)
        #expect(layout.display(near: CGPoint(x: -2000, y: 0))?.id == 1)
        #expect(layout.clamp(CGPoint(x: 5000, y: 100)) == CGPoint(x: 3439, y: 100))
        var moved = layout
        moved.displays[2].frame.origin.x = -1600
        #expect(moved.signature != layout.signature)
        #expect(abs(Self.lower.millimetersPerPoint - 801.0 / 3440) < 1e-9)
    }

    @Test("A model fitted on clean data predicts the targets within a few points")
    func modelFit() throws {
        let data = Self.calibration()
        let model = try #require(GazeModel.fit(data, now: Date(timeIntervalSince1970: 0)))
        #expect(model.accuracy.count == 3)
        #expect(model.accuracy.allSatisfy { $0.medianPoints < 60 }, "\(model.accuracy) lambda \(model.lambda)")
        for target in data.targets.filter({ $0.phase == .grid }) {
            let prediction = try #require(model.predict(Self.features(for: target.point).vector))
            #expect(prediction.displayID == target.displayID)
            #expect(hypot(prediction.point.x - target.point.x, prediction.point.y - target.point.y) < 60)
        }
        #expect(model.predict([1, 2]) == nil)
        #expect(GazeModel.fit(CalibrationData(layout: Self.layout, targets: [], samples: [])) == nil)
    }

    @Test("The One Euro filter passes the first sample, holds a constant and follows a step")
    func oneEuro() {
        var filter = OneEuroFilter(minimumCutoff: 1, beta: 0)
        #expect(filter.filter(5, at: 0) == 5)
        #expect(filter.filter(5, at: 0.033) == 5)
        var value = 5.0
        for step in 1...60 {
            value = filter.filter(10, at: 0.033 + Double(step) * 0.033)
        }
        #expect(value > 9.9 && value <= 10)
        filter.reset()
        #expect(filter.filter(-3, at: 10) == -3)
    }

    @Test("The estimator ignores blinks, smooths and reports the display")
    func estimator() throws {
        let model = try #require(GazeModel.fit(Self.calibration()))
        var estimator = GazeEstimator(model: model)
        let target = Self.layout.displays[0].point(normalized: CGPoint(x: 0.5, y: 0.5))
        var blink = Self.features(for: target)
        blink.blink = 0.9
        #expect(estimator.update(blink) == nil)
        var last: GazeEstimate?
        for frame in 0..<30 {
            last = estimator.update(Self.features(for: target, time: Double(frame) / 30))
        }
        let estimate = try #require(last)
        #expect(estimate.displayID == 2)
        #expect(hypot(estimate.point.x - target.x, estimate.point.y - target.y) < 60)
        #expect(estimate.speed < 1)
    }

    @Test("Eye measurements from synthetic landmarks")
    func extraction() throws {
        var landmarks = [SIMD3<Float>](repeating: SIMD3(0.5, 0.5, 0), count: 478)
        func place(_ index: Int, _ x: Float, _ y: Float) {
            landmarks[index] = SIMD3(x / 1000, y / 1000, 0)
        }
        // Image-left eye from x 300 to 400, iris 10 px right of center; image-right eye from 600 to 700, centered.
        place(33, 300, 500)
        place(133, 400, 500)
        place(159, 350, 485)
        place(145, 350, 515)
        place(468, 360, 500)
        place(362, 600, 500)
        place(263, 700, 500)
        place(386, 650, 490)
        place(374, 650, 510)
        place(473, 650, 500)
        let observation = FaceObservation(
            landmarks: landmarks, blendshapes: ["eyeBlinkLeft": 0.2, "eyeLookOutLeft": 0.4],
            transform: matrix_identity_float4x4, imageWidth: 1000, imageHeight: 1000, timestamp: 2)
        let features = try #require(FeatureExtractor.extract(observation))
        #expect(abs(features.imageLeftEye.horizontal - 0.1) < 1e-5)
        #expect(abs(features.imageRightEye.horizontal) < 1e-5)
        #expect(abs(features.imageLeftEye.openness - 0.3) < 1e-5)
        #expect(abs(features.imageRightEye.openness - 0.2) < 1e-5)
        #expect(abs(features.blendshapeHorizontal - 0.2) < 1e-6)
        #expect(!features.isBlinking)
        #expect(features.vector.count == GazeFeatures.vectorLength)
        let weights = features.eyeWeights
        #expect(weights.left > weights.right)
        var noTransform = observation
        noTransform.transform = nil
        #expect(FeatureExtractor.extract(noTransform) == nil)
    }

    @Test("The calibration store round-trips a model")
    func store() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CalibrationStore(fileURL: root.appendingPathComponent("calibration.json"))
        #expect(store.load() == nil)
        let model = try #require(GazeModel.fit(Self.calibration(), now: Date(timeIntervalSince1970: 1_790_000_000)))
        try store.save(model)
        #expect(store.load() == model)
    }
}
