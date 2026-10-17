import AppKit
import CoreGraphics
import PointerKit

@MainActor
final class EventPoster {
    nonisolated static let tag: Int64 = 0x4559_4554

    private let source = CGEventSource(stateID: .hidSystemState)
    private var clicks = ClickCounter()
    private var pressed: Set<Int> = []

    var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    var isButtonHeld: Bool {
        !pressed.isEmpty
    }

    func move(to point: CGPoint) {
        let from = cursor
        post(.mouseMoved, at: point, button: .left, delta: CGPoint(x: point.x - from.x, y: point.y - from.y))
    }

    func drag(by delta: CGPoint, clamp: (CGPoint) -> CGPoint) {
        guard let primary = pressed.min() else {
            return
        }
        let from = cursor
        let to = clamp(CGPoint(x: from.x + delta.x, y: from.y + delta.y))
        let type: CGEventType =
            switch primary {
            case 1: .leftMouseDragged
            case 2: .rightMouseDragged
            default: .otherMouseDragged
            }
        post(type, at: to, button: Self.mouseButton(primary), delta: CGPoint(x: to.x - from.x, y: to.y - from.y))
    }

    func button(_ number: Int, isDown: Bool) {
        let location = cursor
        let count: Int
        if isDown {
            pressed.insert(number)
            count = clicks.press(
                button: number, at: location, time: ProcessInfo.processInfo.systemUptime,
                interval: NSEvent.doubleClickInterval)
        } else {
            pressed.remove(number)
            count = clicks.releaseCount(button: number)
        }
        let type: CGEventType =
            switch (number, isDown) {
            case (1, true): .leftMouseDown
            case (1, false): .leftMouseUp
            case (2, true): .rightMouseDown
            case (2, false): .rightMouseUp
            case (_, true): .otherMouseDown
            case (_, false): .otherMouseUp
            }
        guard
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: location,
                mouseButton: Self.mouseButton(number))
        else {
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number - 1))
        send(event)
    }

    func scroll(wheel: Int, pan: Int) {
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let lines = ScrollMapping.lines(wheel: wheel, pan: pan, natural: natural)
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: lines.vertical,
                wheel2: lines.horizontal, wheel3: 0)
        else {
            return
        }
        send(event)
    }

    func releaseAll() {
        for number in pressed.sorted() {
            button(number, isDown: false)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, delta: CGPoint) {
        guard
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else {
            return
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y.rounded()))
        send(event)
    }

    private func send(_ event: CGEvent) {
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
        event.post(tap: .cghidEventTap)
    }

    private static func mouseButton(_ number: Int) -> CGMouseButton {
        switch number {
        case 1: .left
        case 2: .right
        default: CGMouseButton(rawValue: UInt32(max(number - 1, 2))) ?? .center
        }
    }
}
