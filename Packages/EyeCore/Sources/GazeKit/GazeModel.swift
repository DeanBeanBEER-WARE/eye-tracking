import CoreGraphics
import Foundation
import TrackingKit

/// One feature vector taken while the user looked at a calibration target.
public struct CalibrationSample: Codable, Equatable, Sendable {
    /// The feature vector (``TrackingKit/GazeFeatures/vector``).
    public var vector: [Double]

    /// The index of the target in ``CalibrationData/targets``.
    public var target: Int

    /// The raw eye landmarks, pose matrix and eye blendshapes (``TrackingKit/FeatureExtractor/raw(_:)``), kept
    /// for offline analysis of new features.
    public var raw: [Float]?

    /// Creates a sample.
    ///
    /// - Parameters:
    ///   - vector: The feature vector.
    ///   - target: The target index.
    ///   - raw: The raw measurements, if recorded.
    public init(vector: [Double], target: Int, raw: [Float]? = nil) {
        self.vector = vector
        self.target = target
        self.raw = raw
    }
}

/// Everything a calibration recorded.
public struct CalibrationData: Codable, Equatable, Sendable {
    /// The displays at calibration time.
    public var layout: ScreenLayout

    /// The targets.
    public var targets: [CalibrationTarget]

    /// The samples.
    public var samples: [CalibrationSample]

    /// The camera the calibration was recorded with (`nil` for calibrations from before this was recorded).
    public var cameraID: String?

    /// Creates calibration data.
    ///
    /// - Parameters:
    ///   - layout: The displays.
    ///   - targets: The targets.
    ///   - samples: The samples.
    ///   - cameraID: The camera.
    public init(
        layout: ScreenLayout, targets: [CalibrationTarget], samples: [CalibrationSample], cameraID: String? = nil
    ) {
        self.layout = layout
        self.targets = targets
        self.samples = samples
        self.cameraID = cameraID
    }
}

/// The cross-validated accuracy on one display.
public struct DisplayAccuracy: Codable, Equatable, Sendable {
    /// The display.
    public var displayID: UInt32

    /// The median error in points.
    public var medianPoints: Double

    /// The median error in millimeters.
    public var medianMillimeters: Double

    /// Creates an accuracy record.
    ///
    /// - Parameters:
    ///   - displayID: The display.
    ///   - medianPoints: The median error in points.
    ///   - medianMillimeters: The median error in millimeters.
    public init(displayID: UInt32, medianPoints: Double, medianMillimeters: Double) {
        self.displayID = displayID
        self.medianPoints = medianPoints
        self.medianMillimeters = medianMillimeters
    }
}

/// The fitted mapping from gaze features to screen points.
///
/// A global ridge model picks the display; a model per display then refines the position on it. Features are
/// standardized and expanded with squares and products of the iris, blendshape and head angle values.
public struct GazeModel: Codable, Equatable, Sendable {
    /// The penalties tried in the cross-validation.
    public static let lambdas: [Double] = [0.1, 0.3, 1, 3, 10, 30, 100]

    /// The minimum number of targets a display needs for its own model.
    static let minimumTargetsPerDisplay = 4

    /// The number of targets from which a display model gets quadratic terms; with fewer it stays linear,
    /// because a quadratic model on few targets extrapolates badly.
    static let quadraticTargetsPerDisplay = 9

    /// The base features that get quadratic terms: iris x and y of both eyes, blendshape x and y, yaw, pitch.
    static let quadraticFeatures = [0, 1, 2, 3, 4, 5, 6, 7]

    struct Axes: Codable, Equatable, Sendable {
        var x: [Double]
        var y: [Double]
    }

    /// The calibration the model was fitted on.
    public var data: CalibrationData

    /// The penalty chosen by the cross-validation.
    public var lambda: Double

    /// The cross-validated accuracy per display.
    public var accuracy: [DisplayAccuracy]

    /// When the model was fitted.
    public var createdAt: Date

    /// The feature vector version the model was fitted on (`nil` for the first version).
    public var featureVersion: Int?

    var mean: [Double]
    var scale: [Double]
    var global: Axes
    var local: [String: Axes]

    /// The displays the model was calibrated for.
    public var layout: ScreenLayout {
        data.layout
    }

    /// Whether the model fits the current feature vector; an older model needs a new calibration.
    public var isCurrent: Bool {
        featureVersion == GazeFeatures.vectorVersion && mean.count == GazeFeatures.vectorLength
    }

    /// Fits a model, choosing the penalty by leave-one-target-out cross-validation.
    ///
    /// - Parameters:
    ///   - data: The calibration.
    ///   - lambdas: The penalties to try.
    ///   - now: The fit time.
    /// - Returns: The model, or `nil` if the data is too small or degenerate.
    public static func fit(_ data: CalibrationData, lambdas: [Double] = lambdas, now: Date = Date()) -> GazeModel? {
        let samples = data.samples.filter { data.targets.indices.contains($0.target) }
        guard let width = samples.first?.vector.count, samples.count >= 10,
            samples.allSatisfy({ $0.vector.count == width })
        else {
            return nil
        }
        let (mean, scale) = standardization(samples.map(\.vector))
        let rows = samples.map { design(standardize($0.vector, mean: mean, scale: scale)) }
        let groups = Dictionary(grouping: samples.indices) { samples[$0].target }
        let linearWidth = width + 1
        var sums: [Int: TargetSums] = [:]
        for (target, members) in groups {
            let display = data.targets[target].displayID
            let targetsOnDisplay = Set(groups.keys.filter { data.targets[$0].displayID == display }).count
            let localWidth = targetsOnDisplay >= quadraticTargetsPerDisplay ? rows[members[0]].count : linearWidth
            sums[target] = TargetSums(members.map { rows[$0] }, target: data.targets[target], localWidth: localWidth)
        }
        var best: (lambda: Double, score: Double, errors: [(UInt32, Double)])?
        for lambda in lambdas {
            var errors: [(UInt32, Double)] = []
            for (target, held) in groups {
                guard let models = fitAxes(sums.filter { $0.key != target }, data: data, lambda: lambda) else {
                    continue
                }
                let predictions = held.compactMap { predict(rows[$0], models: models, layout: data.layout) }
                guard !predictions.isEmpty else {
                    continue
                }
                let estimate = CGPoint(
                    x: median(predictions.map { Double($0.point.x) }), y: median(predictions.map { Double($0.point.y) })
                )
                let goal = data.targets[target].point
                errors.append((data.targets[target].displayID, hypot(estimate.x - goal.x, estimate.y - goal.y)))
            }
            guard !errors.isEmpty else {
                continue
            }
            let score = errors.map(\.1).reduce(0, +) / Double(errors.count)
            if let current = best, current.score <= score {
                continue
            }
            best = (lambda, score, errors)
        }
        guard let best, let models = fitAxes(sums, data: data, lambda: best.lambda) else {
            return nil
        }
        let accuracy = data.layout.displays.compactMap { display -> DisplayAccuracy? in
            let errors = best.errors.filter { $0.0 == display.id }.map(\.1)
            guard !errors.isEmpty else {
                return nil
            }
            let points = median(errors)
            return DisplayAccuracy(
                displayID: display.id, medianPoints: points, medianMillimeters: points * display.millimetersPerPoint)
        }
        return GazeModel(
            data: data, lambda: best.lambda, accuracy: accuracy, createdAt: now,
            featureVersion: GazeFeatures.vectorVersion, mean: mean, scale: scale, global: models.global,
            local: models.local)
    }

    /// Predicts the screen point of a feature vector.
    ///
    /// - Parameter vector: The feature vector.
    /// - Returns: The global point inside a display and that display, or `nil` for a vector of the wrong size.
    public func predict(_ vector: [Double]) -> (point: CGPoint, displayID: UInt32)? {
        guard vector.count == mean.count else {
            return nil
        }
        let row = Self.design(Self.standardize(vector, mean: mean, scale: scale))
        return Self.predict(row, models: (global, local), layout: data.layout)
    }

    /// The normal equations of one target's samples, for the global and for the display model.
    private struct TargetSums {
        var displayID: UInt32
        var global: RidgeRegression.NormalEquations
        var local: RidgeRegression.NormalEquations

        init(_ rows: [[Double]], target: CalibrationTarget, localWidth: Int) {
            displayID = target.displayID
            global = RidgeRegression.NormalEquations(width: rows.first?.count ?? 0)
            local = RidgeRegression.NormalEquations(width: localWidth)
            for row in rows {
                global.add(row, Double(target.point.x), Double(target.point.y))
                local.add(Array(row.prefix(localWidth)), Double(target.normalized.x), Double(target.normalized.y))
            }
        }
    }

    private static func fitAxes(
        _ sums: [Int: TargetSums], data: CalibrationData, lambda: Double
    ) -> (global: Axes, local: [String: Axes])? {
        let parts = Array(sums.values)
        guard let first = parts.first,
            let global = parts.dropFirst().reduce(first.global, { $0 + $1.global }).solve(lambda: lambda)
        else {
            return nil
        }
        var local: [String: Axes] = [:]
        for display in data.layout.displays {
            let own = parts.filter { $0.displayID == display.id }
            guard own.count >= minimumTargetsPerDisplay, let start = own.first,
                let weights = own.dropFirst().reduce(start.local, { $0 + $1.local }).solve(lambda: lambda)
            else {
                continue
            }
            local[String(display.id)] = Axes(x: weights.first, y: weights.second)
        }
        return (Axes(x: global.first, y: global.second), local)
    }

    private static func predict(
        _ row: [Double], models: (global: Axes, local: [String: Axes]), layout: ScreenLayout
    ) -> (point: CGPoint, displayID: UInt32)? {
        let rough = CGPoint(
            x: RidgeRegression.predict(models.global.x, row), y: RidgeRegression.predict(models.global.y, row))
        guard let display = layout.display(near: rough) else {
            return nil
        }
        var point = rough
        if let refined = models.local[String(display.id)] {
            // A display model is linear (bias and features) or quadratic; its weights tell which prefix it uses.
            let localRow = Array(row.prefix(refined.x.count))
            let normalized = CGPoint(
                x: min(max(RidgeRegression.predict(refined.x, localRow), 0), 1),
                y: min(max(RidgeRegression.predict(refined.y, localRow), 0), 1))
            point = display.point(normalized: normalized)
        }
        let frame = display.frame
        point.x = min(max(point.x, frame.minX), frame.maxX - 1)
        point.y = min(max(point.y, frame.minY), frame.maxY - 1)
        return (point, display.id)
    }

    static func standardization(_ vectors: [[Double]]) -> (mean: [Double], scale: [Double]) {
        let width = vectors.first?.count ?? 0
        let count = Double(max(vectors.count, 1))
        var mean = [Double](repeating: 0, count: width)
        for vector in vectors {
            for index in 0..<width {
                mean[index] += vector[index] / count
            }
        }
        var scale = [Double](repeating: 0, count: width)
        for vector in vectors {
            for index in 0..<width {
                scale[index] += (vector[index] - mean[index]) * (vector[index] - mean[index]) / count
            }
        }
        return (mean, scale.map { $0 > 1e-12 ? $0.squareRoot() : 1 })
    }

    static func standardize(_ vector: [Double], mean: [Double], scale: [Double]) -> [Double] {
        zip(vector, zip(mean, scale)).map { ($0 - $1.0) / $1.1 }
    }

    /// The design row: bias, the standardized features, squares and products of the quadratic features.
    static func design(_ standardized: [Double]) -> [Double] {
        var row = [1.0] + standardized
        let chosen = quadraticFeatures.filter { $0 < standardized.count }
        for (position, first) in chosen.enumerated() {
            for second in chosen[position...] {
                row.append(standardized[first] * standardized[second])
            }
        }
        return row
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
