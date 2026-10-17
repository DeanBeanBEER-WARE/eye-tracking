import CoreGraphics
import Foundation
import TrackingKit

public struct CalibrationSample: Codable, Equatable, Sendable {
    public var vector: [Double]

    public var target: Int

    public var raw: [Float]?

    public init(vector: [Double], target: Int, raw: [Float]? = nil) {
        self.vector = vector
        self.target = target
        self.raw = raw
    }
}

public struct CalibrationData: Codable, Equatable, Sendable {
    public var layout: ScreenLayout

    public var targets: [CalibrationTarget]

    public var samples: [CalibrationSample]

    public var cameraID: String?

    public init(
        layout: ScreenLayout, targets: [CalibrationTarget], samples: [CalibrationSample], cameraID: String? = nil
    ) {
        self.layout = layout
        self.targets = targets
        self.samples = samples
        self.cameraID = cameraID
    }
}

public struct DisplayAccuracy: Codable, Equatable, Sendable {
    public var displayID: UInt32

    public var medianPoints: Double

    public var medianMillimeters: Double

    public init(displayID: UInt32, medianPoints: Double, medianMillimeters: Double) {
        self.displayID = displayID
        self.medianPoints = medianPoints
        self.medianMillimeters = medianMillimeters
    }
}

public struct GazeModel: Codable, Equatable, Sendable {
    public static let lambdas: [Double] = [0.1, 0.3, 1, 3, 10, 30, 100]

    static let minimumTargetsPerDisplay = 4

    static let quadraticTargetsPerDisplay = 9

    static let quadraticFeatures = [0, 1, 2, 3, 4, 5, 6, 7]

    struct Axes: Codable, Equatable, Sendable {
        var x: [Double]
        var y: [Double]
    }

    public var data: CalibrationData

    public var lambda: Double

    public var accuracy: [DisplayAccuracy]

    public var createdAt: Date

    public var featureVersion: Int?

    var mean: [Double]
    var scale: [Double]
    var global: Axes
    var local: [String: Axes]

    public var layout: ScreenLayout {
        data.layout
    }

    public var isCurrent: Bool {
        featureVersion == GazeFeatures.vectorVersion && mean.count == GazeFeatures.vectorLength
    }

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

    public func predict(_ vector: [Double]) -> (point: CGPoint, displayID: UInt32)? {
        guard vector.count == mean.count else {
            return nil
        }
        let row = Self.design(Self.standardize(vector, mean: mean, scale: scale))
        return Self.predict(row, models: (global, local), layout: data.layout)
    }

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
