import CoreGraphics
import Foundation

public enum SnapSelector {
    public static let maximumSize = CGSize(width: 700, height: 160)

    public static let centeringSize = CGSize(width: 240, height: 60)

    public static let ambiguityMargin: CGFloat = 10

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

    static func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return hypot(dx, dy)
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

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
