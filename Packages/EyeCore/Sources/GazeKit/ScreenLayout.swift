import CoreGraphics
import Foundation

public struct DisplayInfo: Codable, Equatable, Sendable {
    public var id: UInt32

    public var frame: CGRect

    public var physicalSize: CGSize

    public var isBuiltIn: Bool

    public init(id: UInt32, frame: CGRect, physicalSize: CGSize, isBuiltIn: Bool) {
        self.id = id
        self.frame = frame
        self.physicalSize = physicalSize
        self.isBuiltIn = isBuiltIn
    }

    public var millimetersPerPoint: Double {
        guard physicalSize.width > 0, frame.width > 0 else {
            return 0.25
        }
        return Double(physicalSize.width / frame.width)
    }

    public func point(normalized: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + normalized.x * frame.width, y: frame.minY + normalized.y * frame.height)
    }

    public func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
    }
}

public struct ScreenLayout: Codable, Equatable, Sendable {
    public var displays: [DisplayInfo]

    public init(displays: [DisplayInfo]) {
        self.displays = displays
    }

    public var signature: String {
        displays
            .map { display in
                let frame = display.frame.integral
                return "\(display.isBuiltIn ? "b" : "e"):\(Int(frame.minX)),\(Int(frame.minY)),"
                    + "\(Int(frame.width))x\(Int(frame.height))"
            }
            .sorted()
            .joined(separator: ";")
    }

    public func display(id: UInt32) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    public func display(near point: CGPoint) -> DisplayInfo? {
        if let containing = displays.first(where: { $0.frame.contains(point) }) {
            return containing
        }
        return displays.min { distance(point, to: $0.frame) < distance(point, to: $1.frame) }
    }

    public func clamp(_ point: CGPoint) -> CGPoint {
        guard let display = display(near: point) else {
            return point
        }
        let frame = display.frame
        return CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX - 1), y: min(max(point.y, frame.minY), frame.maxY - 1))
    }

    private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
