import Foundation
import os

public enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    case debug = 10

    case info = 20

    case warning = 30

    case error = 40

    case critical = 50

    public var name: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        case .critical: "CRITICAL"
        }
    }

    public var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        case .critical: .fault
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public protocol LogSink: Sendable {
    func write(level: LogLevel, category: String, message: String)
}

public struct Log: Sendable {
    private static let installedSink = OSAllocatedUnfairLock<(any LogSink)?>(initialState: nil)

    public let category: String

    private let sink: (any LogSink)?
    private let logger: Logger

    public init(_ category: String, sink: (any LogSink)? = nil) {
        self.category = category
        self.sink = sink
        logger = Logger(subsystem: AppInfo.bundleIdentifier, category: category)
    }

    @discardableResult
    public static func bootstrap(_ sink: any LogSink) -> Bool {
        installedSink.withLock { current in
            guard current == nil else {
                return false
            }
            current = sink
            return true
        }
    }

    public func log(_ level: LogLevel, _ message: String) {
        logger.log(level: level.osLogType, "\(message, privacy: .public)")
        let target = sink ?? Log.installedSink.withLock { $0 }
        target?.write(level: level, category: category, message: message)
    }

    public func debug(_ message: String) {
        log(.debug, message)
    }

    public func info(_ message: String) {
        log(.info, message)
    }

    public func warning(_ message: String) {
        log(.warning, message)
    }

    public func error(_ message: String) {
        log(.error, message)
    }

    public func critical(_ message: String) {
        log(.critical, message)
    }
}
