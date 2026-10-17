import CoreGraphics
import Foundation
import Testing

@testable import GazeKit
@testable import PointerKit

@Suite("Pointer")
struct PointerTests {
    static let millimetersPerPoint = 0.25

    static func move(
        _ policy: inout PointerPolicy, _ x: CGFloat, _ y: CGFloat, speed: Double = 0, at time: TimeInterval
    ) -> CGPoint? {
        let estimate = GazeEstimate(point: CGPoint(x: x, y: y), displayID: 1, speed: speed, timestamp: time)
        return policy.target(for: estimate, millimetersPerPoint: millimetersPerPoint, now: time)
    }

    @Test("The first estimate moves the cursor, a resting gaze inside the dead zone keeps it still")
    func deadZone() {
        var policy = PointerPolicy()
        let first = Self.move(&policy, 100, 100, at: 0)
        #expect(first == CGPoint(x: 100, y: 100))
        _ = Self.move(&policy, 100, 100, at: 0.2)
        #expect(!policy.isFollowing)
        let small = Self.move(&policy, 150, 120, at: 0.3)
        #expect(small == nil)
        let jump = Self.move(&policy, 400, 100, speed: 200, at: 0.4)
        #expect(jump == CGPoint(x: 400, y: 100))
        #expect(policy.isFollowing)
        let glide = Self.move(&policy, 410, 100, speed: 50, at: 0.45)
        #expect(glide == CGPoint(x: 410, y: 100))
        _ = Self.move(&policy, 412, 100, speed: 2, at: 0.5)
        _ = Self.move(&policy, 412, 100, speed: 2, at: 0.7)
        #expect(!policy.isFollowing)
        let rest = Self.move(&policy, 440, 110, at: 0.8)
        #expect(rest == nil)
    }

    @Test("A held button freezes the cursor, the release keeps it still briefly and re-anchors without a jump")
    func buttons() {
        var policy = PointerPolicy()
        _ = Self.move(&policy, 100, 100, at: 0)
        policy.button(1, isDown: true, now: 1)
        #expect(policy.isButtonHeld)
        let held = Self.move(&policy, 900, 900, speed: 300, at: 1.1)
        #expect(held == nil)
        policy.button(1, isDown: false, now: 1.2)
        let hold = Self.move(&policy, 900, 900, at: 1.3)
        #expect(hold == nil)
        let anchored = Self.move(&policy, 900, 900, at: 1.6)
        let near = Self.move(&policy, 950, 900, at: 1.7)
        let saccade = Self.move(&policy, 1300, 900, speed: 200, at: 1.8)
        #expect(anchored == nil && near == nil)
        #expect(saccade == CGPoint(x: 1300, y: 900))
    }

    @Test("Trackpad movement pauses gaze and keeps the corrected cursor")
    func manualMovement() {
        var policy = PointerPolicy()
        _ = Self.move(&policy, 100, 100, at: 0)
        policy.manualMovement(now: 1)
        let paused = Self.move(&policy, 600, 100, speed: 200, at: 1.5)
        let anchored = Self.move(&policy, 600, 100, at: 2.3)
        let near = Self.move(&policy, 620, 100, at: 2.4)
        #expect(paused == nil && anchored == nil && near == nil)
        policy.reset()
        let fresh = Self.move(&policy, 620, 100, at: 3)
        #expect(fresh != nil)
    }

    @Test("A landing is reported once per rest and cleared by the next change")
    func landing() {
        var policy = PointerPolicy()
        _ = Self.move(&policy, 100, 100, at: 0)
        #expect(policy.landing == nil)
        _ = Self.move(&policy, 101, 100, at: 0.2)
        #expect(policy.landing == CGPoint(x: 101, y: 100))
        let rested = policy.epoch
        _ = Self.move(&policy, 110, 100, at: 0.3)
        #expect(policy.epoch == rested && policy.landing != nil)
        policy.manualMovement(now: 0.4)
        #expect(policy.epoch > rested && policy.landing == nil)
    }

    @Test("Snapping picks the nearest small element and refuses ambiguous or distant ones")
    func snapping() {
        let point = CGPoint(x: 100, y: 100)
        let button = CGRect(x: 120, y: 90, width: 60, height: 20)
        #expect(SnapSelector.choose(from: [button], near: point, radius: 50) == CGPoint(x: 150, y: 100))
        #expect(SnapSelector.choose(from: [button], near: point, radius: 10) == nil)
        let inside = CGRect(x: 80, y: 90, width: 60, height: 20)
        #expect(SnapSelector.choose(from: [inside], near: point, radius: 50) == CGPoint(x: 110, y: 100))
        let wide = CGRect(x: 0, y: 80, width: 600, height: 40)
        #expect(SnapSelector.choose(from: [wide], near: point, radius: 50) == nil)
        let link = CGRect(x: 95, y: 95, width: 30, height: 10)
        #expect(SnapSelector.choose(from: [wide, link], near: point, radius: 50) == CGPoint(x: 110, y: 100))
        let left = CGRect(x: 40, y: 90, width: 40, height: 20)
        let right = CGRect(x: 122, y: 90, width: 40, height: 20)
        #expect(SnapSelector.choose(from: [left, right], near: point, radius: 50) == nil)
        #expect(
            SnapSelector.choose(from: [CGRect(x: 0, y: 0, width: 2000, height: 1000)], near: point, radius: 50) == nil)
        let samples = SnapSelector.samplePoints(around: point, radius: 40)
        #expect(samples.count == 17 && samples[0] == point)
    }

    @Test("Engagement waits for a steady face and survives short losses")
    func engagement() {
        var tracker = EngagementTracker(releaseAfter: 1.0, engageAfter: 0.4)
        let steps: [(Bool, TimeInterval, Bool)] = [
            (true, 0, false), (true, 0.3, false), (true, 0.4, true), (false, 0.9, true), (true, 1.0, true),
            (false, 1.5, true), (false, 2.0, false), (true, 2.1, false),
        ]
        for (visible, time, expected) in steps {
            let engaged = tracker.update(faceVisible: visible, now: time)
            #expect(engaged == expected, "at \(time)")
        }
        tracker.reset()
        #expect(!tracker.isEngaged)
    }

    @Test("HID values decode to motion, buttons, wheel and tilt")
    func decode() {
        #expect(MouseInput.decode(usagePage: 1, usage: 0x30, value: -3) == .motionX(-3))
        #expect(MouseInput.decode(usagePage: 1, usage: 0x31, value: 0) == nil)
        #expect(MouseInput.decode(usagePage: 1, usage: 0x38, value: 1) == .wheel(1))
        #expect(MouseInput.decode(usagePage: 0x0C, usage: 0x238, value: -1) == .pan(-1))
        #expect(MouseInput.decode(usagePage: 9, usage: 4, value: 1) == .button(4, isDown: true))
        #expect(MouseInput.decode(usagePage: 9, usage: 0, value: 1) == nil)
        #expect(MouseInput.decode(usagePage: 0xFF00, usage: 1, value: 1) == nil)
    }

    @Test("Scroll direction follows the natural scrolling setting")
    func scroll() {
        #expect(ScrollMapping.lines(wheel: 1, pan: 0, natural: false) == (1, 0))
        #expect(ScrollMapping.lines(wheel: 1, pan: 0, natural: true) == (-1, 0))
        #expect(ScrollMapping.lines(wheel: 0, pan: 1, natural: false) == (0, -1))
        #expect(ScrollMapping.lines(wheel: 0, pan: 1, natural: true) == (0, 1))
    }

    @Test("Clicks on one spot within the interval count up")
    func clicks() {
        var counter = ClickCounter()
        let point = CGPoint(x: 10, y: 10)
        let counts = [
            counter.press(button: 1, at: point, time: 0, interval: 0.5),
            counter.press(button: 1, at: CGPoint(x: 12, y: 11), time: 0.3, interval: 0.5),
        ]
        #expect(counts == [1, 2])
        #expect(counter.releaseCount(button: 1) == 2)
        let later = [
            counter.press(button: 1, at: point, time: 0.6, interval: 0.5),
            counter.press(button: 1, at: point, time: 1.5, interval: 0.5),
            counter.press(button: 2, at: point, time: 1.6, interval: 0.5),
        ]
        #expect(later == [3, 1, 1])
        #expect(counter.releaseCount(button: 1) == 1)
    }
}
