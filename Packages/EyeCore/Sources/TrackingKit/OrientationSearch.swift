import Foundation

public struct OrientationSearch: Equatable, Sendable {
    public static let searchAfter: TimeInterval = 3

    public static let tryDuration: TimeInterval = 1.5

    public private(set) var offset: Int

    public private(set) var isLocked = false

    private var startedAt: TimeInterval?

    private var tryingSince: TimeInterval?

    public init(offset: Int = 0) {
        self.offset = ((offset % 360) + 360) % 360 / 90 * 90
    }

    public mutating func update(faceFound: Bool, now: TimeInterval) -> Int? {
        let start = startedAt ?? now
        startedAt = start
        if faceFound {
            isLocked = true
            tryingSince = nil
            return nil
        }
        guard !isLocked else {
            return nil
        }
        if let since = tryingSince {
            guard now - since >= Self.tryDuration else {
                return nil
            }
        } else {
            guard now - start >= Self.searchAfter else {
                return nil
            }
        }
        offset = (offset + 90) % 360
        tryingSince = now
        return offset
    }
}
