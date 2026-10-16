import AppKit
import CoreGraphics
import PointerKit

/// Posts the cursor moves of gaze control and the re-injected buttons, wheel and drags of the seized mouse.
///
/// Every posted event carries ``tag`` in its source user data, so the event monitor can tell them from the input of
/// devices that are not seized (the trackpad).
@MainActor
final class EventPoster {
    /// The source user data of all posted events ("EYET").
    nonisolated static let tag: Int64 = 0x4559_4554

    private let source = CGEventSource(stateID: .hidSystemState)
    private var clicks = ClickCounter()
    private var pressed: Set<Int> = []

    /// The current cursor position in global points.
    var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Whether a re-injected button is held.
    var isButtonHeld: Bool {
        !pressed.isEmpty
    }

    /// Moves the cursor.
    ///
    /// - Parameter point: The new position in global points.
    func move(to point: CGPoint) {
        let from = cursor
        post(.mouseMoved, at: point, button: .left, delta: CGPoint(x: point.x - from.x, y: point.y - from.y))
    }

    /// Drags with the held buttons by a relative distance.
    ///
    /// - Parameters:
    ///   - delta: The distance in points.
    ///   - clamp: Keeps the new position on a display.
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

    /// Presses or releases a button at the cursor.
    ///
    /// - Parameters:
    ///   - number: The button number from 1.
    ///   - isDown: Whether the button goes down.
    func button(_ number: Int, isDown: Bool) {
        let location = cursor
        let count: Int
        if isDown {
            pressed.insert(number)
            count = clicks.press(
                button: number, at: location, time: ProcessInfo.processInfo.systemUptime,
                interval: NSEvent.doubleClickInterval)
        } else {
            // A release without a recorded press is posted too: the system may have seen the press before the
            // mouse was seized.
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

    /// Scrolls by wheel and tilt notches.
    ///
    /// - Parameters:
    ///   - wheel: Wheel notches, positive away from the user.
    ///   - pan: Tilt notches, positive to the right.
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

    /// Releases every held button, before the mouse is given back to the system.
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
