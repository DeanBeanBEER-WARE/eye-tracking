import Foundation

/// The One Euro filter (Casiez et al. 2012): strong smoothing at rest, little lag in fast movements.
public struct OneEuroFilter: Sendable {
    /// The cutoff frequency at rest in Hz; lower values smooth more.
    public var minimumCutoff: Double

    /// How fast the cutoff rises with speed; higher values lag less in fast movements.
    public var beta: Double

    /// The cutoff frequency of the speed estimate in Hz.
    public var derivativeCutoff: Double

    private var value: Double?
    private var derivative: Double = 0
    private var time: TimeInterval?

    /// Creates a filter.
    ///
    /// - Parameters:
    ///   - minimumCutoff: The cutoff frequency at rest in Hz.
    ///   - beta: The speed coefficient.
    ///   - derivativeCutoff: The cutoff frequency of the speed estimate in Hz.
    public init(minimumCutoff: Double, beta: Double, derivativeCutoff: Double = 1) {
        self.minimumCutoff = minimumCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// Filters the next sample.
    ///
    /// - Parameters:
    ///   - sample: The raw value.
    ///   - timestamp: The sample time in seconds.
    /// - Returns: The filtered value.
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

    /// Forgets the history, so the next sample passes unfiltered.
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
