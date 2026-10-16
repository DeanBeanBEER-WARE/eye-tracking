import CoreGraphics
import Foundation

/// A point the user looks at during calibration.
public struct CalibrationTarget: Codable, Equatable, Sendable {
    /// What the user does while the target is shown.
    public enum Phase: String, Codable, Sendable {
        /// Looks at the target with a still head.
        case grid

        /// Keeps looking at the target while moving the head slightly, so the model learns head movement.
        case headMovement
    }

    /// The display the target is on.
    public var displayID: UInt32

    /// The position on the display, (0, 0) top left and (1, 1) bottom right.
    public var normalized: CGPoint

    /// The position in global points.
    public var point: CGPoint

    /// The phase.
    public var phase: Phase

    /// Creates a target.
    ///
    /// - Parameters:
    ///   - displayID: The display.
    ///   - normalized: The position on the display.
    ///   - point: The position in global points.
    ///   - phase: The phase.
    public init(displayID: UInt32, normalized: CGPoint, point: CGPoint, phase: Phase) {
        self.displayID = displayID
        self.normalized = normalized
        self.point = point
        self.phase = phase
    }
}

/// Creates the target sequence of a calibration.
public enum CalibrationPlan {
    /// The seconds a grid target waits for the eyes to settle before samples are taken.
    public static let settleTime: TimeInterval = 0.7

    /// The seconds samples are taken at a grid target.
    public static let gridSampleTime: TimeInterval = 1.0

    /// The seconds samples are taken at a head movement target.
    public static let headMovementSampleTime: TimeInterval = 3.0

    /// The targets for all displays: a 5x3 grid on wide displays, 3x3 on the others, built-in display first,
    /// then the others from bottom to top, each grid in snake order; followed by one head movement target in the
    /// center of every display.
    ///
    /// - Parameter layout: The displays.
    /// - Returns: The targets in display order.
    public static func targets(for layout: ScreenLayout) -> [CalibrationTarget] {
        let ordered = layout.displays.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn
            }
            return lhs.frame.maxY > rhs.frame.maxY
        }
        var targets: [CalibrationTarget] = []
        for display in ordered {
            let wide = display.frame.width / max(display.frame.height, 1) >= 1.9
            let columns: [CGFloat] = wide ? [0.06, 0.28, 0.5, 0.72, 0.94] : [0.08, 0.5, 0.92]
            let rows: [CGFloat] = wide ? [0.1, 0.5, 0.9] : [0.12, 0.5, 0.88]
            for (rowIndex, y) in rows.enumerated() {
                let line = rowIndex.isMultiple(of: 2) ? columns : columns.reversed()
                for x in line {
                    let normalized = CGPoint(x: x, y: y)
                    targets.append(
                        CalibrationTarget(
                            displayID: display.id, normalized: normalized, point: display.point(normalized: normalized),
                            phase: .grid))
                }
            }
        }
        for display in ordered {
            let center = CGPoint(x: 0.5, y: 0.5)
            targets.append(
                CalibrationTarget(
                    displayID: display.id, normalized: center, point: display.point(normalized: center),
                    phase: .headMovement))
        }
        return targets
    }
}
