import CoreGraphics
import Foundation

/// Picks the clickable element the cursor snaps to after the gaze landed.
public enum SnapSelector {
    /// Elements larger than this in either dimension (text areas, web views) are not snap targets.
    public static let maximumSize = CGSize(width: 700, height: 160)

    /// The cursor moves to the center of an element it is already inside only if the element is at most this
    /// large; in larger elements the gaze point is good enough.
    public static let centeringSize = CGSize(width: 240, height: 60)

    /// Two candidates closer than this to the same distance make the choice ambiguous, so nothing snaps.
    public static let ambiguityMargin: CGFloat = 10

    /// Chooses the snap point.
    ///
    /// - Parameters:
    ///   - frames: The frames of the clickable elements near the landing point, in global points.
    ///   - point: The landing point.
    ///   - radius: The largest distance from the point to an element.
    /// - Returns: The center of the chosen element, or `nil` if none qualifies or the choice is ambiguous.
    public static func choose(from frames: [CGRect], near point: CGPoint, radius: CGFloat) -> CGPoint? {
        let candidates =
            frames
            .filter { !$0.isEmpty && $0.width <= maximumSize.width && $0.height <= maximumSize.height }
            .map { (frame: $0, distance: distance(from: point, to: $0)) }
            .filter { $0.distance <= radius }
            .sorted { lhs, rhs in
                lhs.distance != rhs.distance ? lhs.distance < rhs.distance : area(lhs.frame) < area(rhs.frame)
            }
        guard let best = candidates.first else {
            return nil
        }
        let center = CGPoint(x: best.frame.midX, y: best.frame.midY)
        if best.distance == 0 {
            let small = best.frame.width <= centeringSize.width && best.frame.height <= centeringSize.height
            return small ? center : nil
        }
        let rival = candidates.dropFirst().first { other in
            !other.frame.contains(best.frame) && !best.frame.contains(other.frame)
        }
        if let rival, rival.distance - best.distance < ambiguityMargin {
            return nil
        }
        return center
    }

    /// The distance from a point to a rectangle, 0 inside.
    static func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return hypot(dx, dy)
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

    /// The sample points around a landing point for the element search: the point itself and two rings.
    ///
    /// - Parameters:
    ///   - point: The landing point.
    ///   - radius: The outer ring radius.
    /// - Returns: The sample points, the landing point first.
    public static func samplePoints(around point: CGPoint, radius: CGFloat) -> [CGPoint] {
        var points = [point]
        for (ring, count) in [(radius * 0.45, 6), (radius, 10)] {
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi
                points.append(CGPoint(x: point.x + ring * CGFloat(cos(angle)), y: point.y + ring * CGFloat(sin(angle))))
            }
        }
        return points
    }
}
