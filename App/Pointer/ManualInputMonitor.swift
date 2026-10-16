import CoreGraphics
import CoreKit
import Foundation

/// Watches the pointer events of all devices that are not seized (the trackpad) with a listen-only event tap.
@MainActor
final class ManualInputMonitor {
    private let log = Log("Pointer")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Called when a device other than the seized mouse moves the cursor or presses a button.
    var onManualInput: (() -> Void)?

    /// Starts watching.
    ///
    /// - Returns: Whether the event tap could be created.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else {
            return true
        }
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown,
            .otherMouseDown,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
                callback: { _, type, event, context in
                    if let context {
                        let monitor = Unmanaged<ManualInputMonitor>.fromOpaque(context).takeUnretainedValue()
                        let isOwn = event.getIntegerValueField(.eventSourceUserData) == EventPoster.tag
                        MainActor.assumeIsolated {
                            monitor.received(type, isOwn: isOwn)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }, userInfo: context)
        else {
            log.error("Could not create the event tap for trackpad detection.")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    /// Stops watching.
    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
    }

    private func received(_ type: CGEventType, isOwn: Bool) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        if !isOwn {
            onManualInput?()
        }
    }
}
