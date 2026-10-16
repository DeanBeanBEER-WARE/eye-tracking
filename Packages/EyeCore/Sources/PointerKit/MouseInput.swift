import CoreGraphics
import Foundation

/// One input value of a seized mouse, decoded from its HID usage.
public enum MouseInput: Equatable, Sendable {
    /// Relative horizontal motion in device counts.
    case motionX(Int)

    /// Relative vertical motion in device counts, positive downwards.
    case motionY(Int)

    /// A button change; buttons are numbered from 1 (left, right, middle, back, forward).
    case button(Int, isDown: Bool)

    /// Wheel notches, positive away from the user.
    case wheel(Int)

    /// Tilt or horizontal wheel notches, positive to the right.
    case pan(Int)

    /// The HID usage pages and usages of a mouse.
    enum Usage {
        static let genericDesktop: UInt32 = 0x01
        static let button: UInt32 = 0x09
        static let consumer: UInt32 = 0x0C
        static let x: UInt32 = 0x30
        static let y: UInt32 = 0x31
        static let wheel: UInt32 = 0x38
        static let acPan: UInt32 = 0x238
    }

    /// Decodes an input value.
    ///
    /// - Parameters:
    ///   - usagePage: The HID usage page of the element.
    ///   - usage: The HID usage of the element.
    ///   - value: The integer value.
    /// - Returns: The input, or `nil` for an element that does not matter or a zero motion.
    public static func decode(usagePage: UInt32, usage: UInt32, value: Int) -> MouseInput? {
        switch (usagePage, usage) {
        case (Usage.genericDesktop, Usage.x):
            value == 0 ? nil : .motionX(value)
        case (Usage.genericDesktop, Usage.y):
            value == 0 ? nil : .motionY(value)
        case (Usage.genericDesktop, Usage.wheel):
            value == 0 ? nil : .wheel(value)
        case (Usage.consumer, Usage.acPan):
            value == 0 ? nil : .pan(value)
        case (Usage.button, let number) where number >= 1 && number <= 32:
            .button(Int(number), isDown: value != 0)
        default:
            nil
        }
    }
}

/// Converts wheel and tilt notches to scroll event line deltas.
public enum ScrollMapping {
    /// The line deltas of a scroll wheel event.
    ///
    /// Posted events bypass the system's scroll direction setting, so "natural" scrolling is applied here.
    ///
    /// - Parameters:
    ///   - wheel: Wheel notches, positive away from the user.
    ///   - pan: Tilt notches, positive to the right.
    ///   - natural: Whether the system scrolls in the "natural" direction.
    /// - Returns: The vertical delta (positive scrolls up) and the horizontal delta (positive scrolls left).
    public static func lines(wheel: Int, pan: Int, natural: Bool) -> (vertical: Int32, horizontal: Int32) {
        let vertical = Int32(clamping: natural ? -wheel : wheel)
        let horizontal = Int32(clamping: natural ? pan : -pan)
        return (vertical, horizontal)
    }
}

/// Counts consecutive clicks for the click state of posted mouse events.
public struct ClickCounter: Sendable {
    /// The largest distance in points between the clicks of a double click.
    public static let slop: CGFloat = 4

    private var last: (button: Int, point: CGPoint, time: TimeInterval, count: Int)?

    /// Creates a counter.
    public init() {}

    /// Records a button press.
    ///
    /// - Parameters:
    ///   - button: The button number.
    ///   - point: The cursor position.
    ///   - time: The press time in seconds.
    ///   - interval: The system double click interval in seconds.
    /// - Returns: The click count, 1 for a single click.
    public mutating func press(button: Int, at point: CGPoint, time: TimeInterval, interval: TimeInterval) -> Int {
        var count = 1
        if let last, last.button == button, time - last.time <= interval,
            hypot(point.x - last.point.x, point.y - last.point.y) <= Self.slop
        {
            count = last.count + 1
        }
        last = (button, point, time, count)
        return count
    }

    /// The click count of the release that ends the last press.
    ///
    /// - Parameter button: The button number.
    /// - Returns: The count of the last press of this button, or 1.
    public func releaseCount(button: Int) -> Int {
        guard let last, last.button == button else {
            return 1
        }
        return last.count
    }
}
