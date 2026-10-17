import Foundation

public struct OneEuroFilter: Sendable {
    public var minimumCutoff: Double

    public var beta: Double

    public var derivativeCutoff: Double

    private var value: Double?
    private var derivative: Double = 0
    private var time: TimeInterval?

    public init(minimumCutoff: Double, beta: Double, derivativeCutoff: Double = 1) {
        self.minimumCutoff = minimumCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func filter(_ sample: Double, at timestamp: TimeInterval) -> Double {
        guard let previous = value, let lastTime = time, timestamp > lastTime else {
            value = sample
            time = timestamp
            return sample
        }
        let interval = timestamp - lastTime
        let rawDerivative = (sample - previous) / interval
        derivative += Self.alpha(cutoff: derivativeCutoff, interval: interval) * (rawDerivative - derivative)
        let cutoff = minimumCutoff + beta * abs(derivative)
        let filtered = previous + Self.alpha(cutoff: cutoff, interval: interval) * (sample - previous)
        value = filtered
        time = timestamp
        return filtered
    }

    public mutating func reset() {
        value = nil
        derivative = 0
        time = nil
    }

    private static func alpha(cutoff: Double, interval: TimeInterval) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / interval)
    }
}
