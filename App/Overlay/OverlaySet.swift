import AppKit
import CoreGraphics

struct OverlayContent {
    struct Target {
        var point: CGPoint
        var ring: CGFloat
    }

    var dimmed = false

    var target: Target?

    var gazeDot: CGPoint?

    var message: String?

    var messageAnchor: CGPoint?
}

@MainActor
final class OverlaySet {
    private var windows: [(window: OverlayWindow, view: OverlayView)] = []

    var onEscape: (() -> Void)?

    init(interactive: Bool) {
        for screen in NSScreen.screens {
            guard let id = DisplayLayoutReader.displayID(of: screen) else {
                continue
            }
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.acceptsKey = interactive
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            let view = OverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size), displayFrame: CGDisplayBounds(id))
            window.contentView = view
            window.onEscape = { [weak self] in self?.onEscape?() }
            window.setFrame(screen.frame, display: false)
            windows.append((window, view))
        }
    }

    func show() {
        for entry in windows {
            entry.window.orderFrontRegardless()
        }
        if let main = windows.first, main.window.acceptsKey {
            NSApp.activate()
            main.window.makeKey()
        }
    }

    func update(_ content: OverlayContent) {
        for entry in windows {
            entry.view.content = content
        }
    }

    func close() {
        for entry in windows {
            entry.window.orderOut(nil)
            entry.window.close()
        }
        windows.removeAll()
    }
}

final class OverlayWindow: NSWindow {
    var acceptsKey = false

    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        acceptsKey
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

final class OverlayView: NSView {
    private let displayFrame: CGRect

    var content = OverlayContent() {
        didSet {
            let messageMoved = content.message != nil && content.messageAnchor != oldValue.messageAnchor
            if content.dimmed != oldValue.dimmed || content.message != oldValue.message || messageMoved {
                needsDisplay = true
                return
            }
            for rect in [oldValue.target, content.target].compactMap({ $0.map(targetRect) }) {
                setNeedsDisplay(rect)
            }
            for rect in [oldValue.gazeDot, content.gazeDot].compactMap({ $0.map(dotRect) }) {
                setNeedsDisplay(rect)
            }
        }
    }

    init(frame: NSRect, displayFrame: CGRect) {
        self.displayFrame = displayFrame
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        if content.dimmed {
            NSColor.black.withAlphaComponent(0.55).setFill()
            dirtyRect.fill()
        }
        if let target = content.target, displayFrame.contains(target.point) {
            drawTarget(local(target.point), ring: target.ring)
        }
        if let dot = content.gazeDot, displayFrame.contains(dot) {
            let circle = NSBezierPath(ovalIn: dotRect(dot).insetBy(dx: 2, dy: 2))
            NSColor.systemRed.withAlphaComponent(0.35).setFill()
            circle.fill()
            NSColor.systemRed.withAlphaComponent(0.9).setStroke()
            circle.lineWidth = 2
            circle.stroke()
        }
        if let message = content.message, let anchor = content.messageAnchor, displayFrame.contains(anchor) {
            drawMessage(message)
        }
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - displayFrame.minX, y: point.y - displayFrame.minY)
    }

    private func targetRect(_ target: OverlayContent.Target) -> NSRect {
        let center = local(target.point)
        let radius = max(target.ring, 9) + 4
        return NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func dotRect(_ point: CGPoint) -> NSRect {
        let center = local(point)
        return NSRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60)
    }

    private func drawTarget(_ center: CGPoint, ring: CGFloat) {
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let outer = NSBezierPath(
            ovalIn: NSRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
        outer.lineWidth = 3
        outer.stroke()
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
    }

    private func drawMessage(_ message: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: message, attributes: attributes)
        let width = min(bounds.width - 80, 900)
        let size = text.boundingRect(
            with: NSSize(width: width, height: 400), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let box = NSRect(
            x: (bounds.width - width) / 2 - 20, y: bounds.height * 0.32 - 16, width: width + 40,
            height: size.height + 32)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
        text.draw(
            with: NSRect(x: box.minX + 20, y: box.minY + 16, width: width, height: size.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
