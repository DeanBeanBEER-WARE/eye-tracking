import CoreGraphics
import Foundation

public enum MouseInput: Equatable, Sendable {
    case motionX(Int)

    case motionY(Int)

    case button(Int, isDown: Bool)

    case wheel(Int)

    case pan(Int)

    enum Usage {
        static let genericDesktop: UInt32 = 0x01
        static let button: UInt32 = 0x09
        static let consumer: UInt32 = 0x0C
        static let x: UInt32 = 0x30
        static let y: UInt32 = 0x31
        static let wheel: UInt32 = 0x38
        static let acPan: UInt32 = 0x238
    }

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

public enum ScrollMapping {
    public static func lines(wheel: Int, pan: Int, natural: Bool) -> (vertical: Int32, horizontal: Int32) {
        let vertical = Int32(clamping: natural ? -wheel : wheel)
        let horizontal = Int32(clamping: natural ? pan : -pan)
        return (vertical, horizontal)
    }
}

public struct ClickCounter: Sendable {
    public static let slop: CGFloat = 4

    private var last: (button: Int, point: CGPoint, time: TimeInterval, count: Int)?

    public init() {}

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

    public func releaseCount(button: Int) -> Int {
        guard let last, last.button == button else {
            return 1
        }
        return last.count
    }
}
