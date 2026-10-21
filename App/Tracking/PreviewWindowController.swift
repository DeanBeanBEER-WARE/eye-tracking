import AppKit
import CoreKit
import TrackingKit

@MainActor
final class PreviewWindowController: NSObject, NSWindowDelegate {
    private let tracking: TrackingController
    private var window: NSWindow?
    private var view: PreviewView?

    var isVisible: Bool {
        window != nil
    }

    init(tracking: TrackingController) {
        self.tracking = tracking
    }

    func toggle() {
        if let window {
            window.close()
        } else {
            show()
        }
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = PreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = Self.title(for: tracking.activeCameraName)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.view = view
        view.waitingFor = tracking.activeCameraName
        let engine = tracking.engine
        engine.setPreviewHandler { [weak view] image, observation in
            let statistics = engine.statistics
            DispatchQueue.main.async {
                view?.show(image: image, observation: observation, statistics: statistics)
            }
        }
        tracking.acquire(.preview)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func cameraSelected(_ name: String) {
        window?.title = Self.title(for: name)
        view?.reset(waitingFor: name)
    }

    func cameraStarted(_ name: String) {
        window?.title = Self.title(for: name)
    }

    private static func title(for camera: String) -> String {
        camera.isEmpty ? String(localized: "preview.title") : String(localized: "preview.title.camera \(camera)")
    }

    func windowWillClose(_ notification: Notification) {
        tracking.engine.setPreviewHandler(nil)
        tracking.release(.preview)
        window = nil
        view = nil
    }
}

final class PreviewView: NSView {
    private static let eyeCorners = [33, 133, 362, 263]
    private static let eyelids = [159, 145, 386, 374]
    private static let irisCenters = [468, 473]
    private static let irisRings = [469, 470, 471, 472, 474, 475, 476, 477]

    private var image: CGImage?
    private var observation: FaceObservation?
    private var statistics = TrackingStatistics()

    var waitingFor = ""

    override var isFlipped: Bool {
        true
    }

    func reset(waitingFor camera: String) {
        waitingFor = camera
        image = nil
        observation = nil
        needsDisplay = true
    }

    func show(image: CGImage, observation: FaceObservation?, statistics: TrackingStatistics) {
        self.image = image
        self.observation = observation
        self.statistics = statistics
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            drawStatus(
                waitingFor.isEmpty
                    ? String(localized: "preview.starting") : String(localized: "preview.waiting \(waitingFor)"))
            return
        }
        let frame = imageFrame(width: CGFloat(image.width), height: CGFloat(image.height))
        context.saveGState()
        context.translateBy(x: frame.midX, y: frame.midY)
        context.scaleBy(x: -1, y: -1)
        context.draw(
            image, in: CGRect(x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height))
        context.restoreGState()
        if let observation {
            drawLandmarks(observation, in: frame)
        }
        drawStatus(statusText())
    }

    private func imageFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let scale = min(bounds.width / width, bounds.height / height)
        let size = CGSize(width: width * scale, height: height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width,
            height: size.height)
    }

    private func point(_ observation: FaceObservation, _ index: Int, in frame: CGRect) -> CGPoint {
        let landmark = observation.landmarks[index]
        return CGPoint(
            x: frame.minX + (1 - CGFloat(landmark.x)) * frame.width, y: frame.minY + CGFloat(landmark.y) * frame.height)
    }

    private func drawLandmarks(_ observation: FaceObservation, in frame: CGRect) {
        let dots: [(indices: [Int], color: NSColor, radius: CGFloat)] = [
            (Self.eyeCorners, .systemYellow, 3),
            (Self.eyelids, .systemOrange, 2.5),
            (Self.irisRings, .systemTeal, 2),
            (Self.irisCenters, .systemGreen, 3.5),
        ]
        for dot in dots {
            dot.color.setFill()
            for index in dot.indices {
                let center = point(observation, index, in: frame)
                NSBezierPath(
                    ovalIn: NSRect(
                        x: center.x - dot.radius, y: center.y - dot.radius, width: dot.radius * 2,
                        height: dot.radius * 2)
                ).fill()
            }
        }
    }

    private func statusText() -> String {
        var parts = [
            String(
                localized:
                    "preview.stats \(Int(statistics.framesPerSecond.rounded())) \(Int(statistics.inferenceMilliseconds.rounded()))"
            )
        ]
        if let observation {
            parts.append(String(localized: "preview.face"))
            if let transform = observation.transform {
                let pose = HeadPose(matrix: transform)
                parts.append(
                    String(
                        localized:
                            "preview.pose \(Int(pose.yaw.rounded())) \(Int(pose.pitch.rounded())) \(Int(pose.roll.rounded()))"
                    ))
            }
        } else {
            parts.append(String(localized: "preview.no_face"))
        }
        return parts.joined(separator: "  ·  ")
    }

    private func drawStatus(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6),
        ]
        NSAttributedString(string: " \(text) ", attributes: attributes).draw(at: NSPoint(x: 8, y: 8))
    }
}
