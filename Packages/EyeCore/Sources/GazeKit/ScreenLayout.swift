import CoreGraphics
import Foundation

/// One display in CoreGraphics global coordinates (points, origin at the top left of the main display).
public struct DisplayInfo: Codable, Equatable, Sendable {
    /// The CoreGraphics display identifier.
    public var id: UInt32

    /// The display frame in global points.
    public var frame: CGRect

    /// The physical size in millimeters, or zero if unknown.
    public var physicalSize: CGSize

    /// Whether this is the built-in display.
    public var isBuiltIn: Bool

    /// Creates a display description.
    ///
    /// - Parameters:
    ///   - id: The display identifier.
    ///   - frame: The frame in global points.
    ///   - physicalSize: The physical size in millimeters.
    ///   - isBuiltIn: Whether this is the built-in display.
    public init(id: UInt32, frame: CGRect, physicalSize: CGSize, isBuiltIn: Bool) {
        self.id = id
        self.frame = frame
        self.physicalSize = physicalSize
        self.isBuiltIn = isBuiltIn
    }

    /// Millimeters per point, assuming 0.25 mm if the physical size is unknown.
    public var millimetersPerPoint: Double {
        guard physicalSize.width > 0, frame.width > 0 else {
            return 0.25
        }
        return Double(physicalSize.width / frame.width)
    }

    /// Converts a position relative to the display to global points.
    ///
    /// - Parameter normalized: The position, (0, 0) top left and (1, 1) bottom right.
    /// - Returns: The global point.
    public func point(normalized: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + normalized.x * frame.width, y: frame.minY + normalized.y * frame.height)
    }

    /// Converts a global point to a position relative to the display.
    ///
    /// - Parameter point: The global point.
    /// - Returns: The relative position, (0, 0) top left and (1, 1) bottom right.
    public func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
    }
}

/// The arrangement of all displays, which a calibration belongs to.
public struct ScreenLayout: Codable, Equatable, Sendable {
    /// The displays.
    public var displays: [DisplayInfo]

    /// Creates a layout.
    ///
    /// - Parameter displays: The displays.
    public init(displays: [DisplayInfo]) {
        self.displays = displays
    }

    /// A text that changes whenever a display is added, removed, resized or moved.
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

    /// The display with an identifier.
    ///
    /// - Parameter id: The display identifier.
    /// - Returns: The display, or `nil` if the layout has none with this identifier.
    public func display(id: UInt32) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    /// The display that contains a point, or else the nearest one.
    ///
    /// - Parameter point: The global point.
    /// - Returns: The display, or `nil` for an empty layout.
    public func display(near point: CGPoint) -> DisplayInfo? {
        if let containing = displays.first(where: { $0.frame.contains(point) }) {
            return containing
        }
        return displays.min { distance(point, to: $0.frame) < distance(point, to: $1.frame) }
    }

    /// Moves a point into the nearest display.
    ///
    /// - Parameter point: The global point.
    /// - Returns: The point inside a display.
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
