import CoreGraphics
import Foundation

public struct CalibrationTarget: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case grid

        case headMovement
    }

    public var displayID: UInt32

    public var normalized: CGPoint

    public var point: CGPoint

    public var phase: Phase

    public init(displayID: UInt32, normalized: CGPoint, point: CGPoint, phase: Phase) {
        self.displayID = displayID
        self.normalized = normalized
        self.point = point
        self.phase = phase
    }
}

public enum CalibrationPlan {
    public static let settleTime: TimeInterval = 0.7

    public static let gridSampleTime: TimeInterval = 1.0

    public static let headMovementSampleTime: TimeInterval = 3.0

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
