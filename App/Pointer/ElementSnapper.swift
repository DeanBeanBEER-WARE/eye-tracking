import ApplicationServices
import CoreGraphics
import CoreKit
import Foundation
import PointerKit

final class ElementSnapper: @unchecked Sendable {
    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem",
        "AXMenuBarItem", "AXTextField", "AXComboBox", "AXDisclosureTriangle", "AXIncrementor", "AXSearchField",
        "AXDockItem", "AXTab",
    ]

    private static let pressableRoles: Set<String> = ["AXImage", "AXGroup", "AXStaticText", "AXCell", "AXRow"]

    private static let ancestorDepth = 3

    private let queue = DispatchQueue(label: "com.deanbean.eyetracking.snap", qos: .userInteractive)
    private let systemWide = AXUIElementCreateSystemWide()
    private let ownProcess = ProcessInfo.processInfo.processIdentifier
    private let log = Log("Snap")

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

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
