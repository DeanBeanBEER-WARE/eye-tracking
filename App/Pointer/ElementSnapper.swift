import ApplicationServices
import CoreGraphics
import CoreKit
import Foundation
import PointerKit

/// Finds clickable elements near a point with the Accessibility API, off the main thread.
///
/// The search hit-tests a few points around the landing point, walks up from each hit to the nearest clickable
/// ancestor and collects the frames. Every Accessibility call has a short timeout, so a busy app cannot stall it.
final class ElementSnapper: @unchecked Sendable {
    /// The roles that are clickable by themselves.
    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem",
        "AXMenuBarItem", "AXTextField", "AXComboBox", "AXDisclosureTriangle", "AXIncrementor", "AXSearchField",
        "AXDockItem", "AXTab",
    ]

    /// The roles that count as clickable when they offer the press action.
    private static let pressableRoles: Set<String> = ["AXImage", "AXGroup", "AXStaticText", "AXCell", "AXRow"]

    /// The ancestors checked above a hit element.
    private static let ancestorDepth = 3

    private let queue = DispatchQueue(label: "com.deanbean.eyetracking.snap", qos: .userInteractive)
    private let systemWide = AXUIElementCreateSystemWide()
    private let ownProcess = ProcessInfo.processInfo.processIdentifier
    private let log = Log("Snap")

    /// Creates the snapper.
    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    /// Whether the app may use the Accessibility API.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system for Accessibility; macOS shows its prompt.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, a global var that strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Searches for the snap point near a landing point.
    ///
    /// - Parameters:
    ///   - point: The landing point in global points.
    ///   - radius: The search radius in points.
    ///   - completion: Receives the snap point, or `nil`, on the main thread.
    func snapPoint(near point: CGPoint, radius: CGFloat, completion: @escaping @MainActor @Sendable (CGPoint?) -> Void)
    {
        queue.async { [self] in
            let started = ProcessInfo.processInfo.systemUptime
            let frames = clickableFrames(near: point, radius: radius)
            let target = SnapSelector.choose(from: frames, near: point, radius: radius)
            let milliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            if milliseconds > 150 {
                log.debug("Slow element search: \(milliseconds) ms for \(frames.count) frames.")
            }
            DispatchQueue.main.async {
                completion(target)
            }
        }
    }

    private func clickableFrames(near point: CGPoint, radius: CGFloat) -> [CGRect] {
        var seen: Set<AXUIElement> = []
        var frames: [CGRect] = []
        for sample in SnapSelector.samplePoints(around: point, radius: radius) {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(sample.x), Float(sample.y), &hit) == .success,
                let hit
            else {
                continue
            }
            var pid: pid_t = 0
            if AXUIElementGetPid(hit, &pid) == .success, pid == ownProcess {
                continue
            }
            var element: AXUIElement? = hit
            for _ in 0...Self.ancestorDepth {
                guard let current = element, seen.insert(current).inserted else {
                    break
                }
                if isClickable(current) {
                    if let frame = frame(of: current) {
                        frames.append(frame)
                    }
                    break
                }
                element = attribute(current, kAXParentAttribute) as AXUIElement?
            }
        }
        return frames
    }

    private func isClickable(_ element: AXUIElement) -> Bool {
        guard let role: String = attribute(element, kAXRoleAttribute) else {
            return false
        }
        if Self.clickableRoles.contains(role) {
            return true
        }
        guard Self.pressableRoles.contains(role) else {
            return false
        }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success, let names = actions as? [String] else {
            return false
        }
        return names.contains(kAXPressAction)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
            let sizeValue: AXValue = attribute(element, kAXSizeAttribute)
        else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
