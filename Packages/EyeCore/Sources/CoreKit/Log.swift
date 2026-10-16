import Foundation
import os

/// The severity of a log message.
public enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    /// Diagnostic details.
    case debug = 10

    /// Normal operation.
    case info = 20

    /// An unexpected but handled situation.
    case warning = 30

    /// A failed operation.
    case error = 40

    /// A failure that may end the application.
    case critical = 50

    /// The upper-case level name written to the log file, for example `WARNING`.
    public var name: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        case .critical: "CRITICAL"
        }
    }

    /// The matching unified logging type.
    public var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        case .critical: .fault
        }
    }

    /// Compares two levels by severity.
    ///
    /// - Parameters:
    ///   - lhs: The first level.
    ///   - rhs: The second level.
    /// - Returns: `true` if `lhs` is less severe than `rhs`.
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A destination for log messages, installed once at startup.
public protocol LogSink: Sendable {
    /// Writes one message.
    ///
    /// - Parameters:
    ///   - level: The severity.
    ///   - category: The component that logged the message.
    ///   - message: The message text.
    func write(level: LogLevel, category: String, message: String)
}

/// A logger for one component.
///
/// Every message goes to the unified logging system (subsystem = bundle identifier) and to the sink installed with
/// ``bootstrap(_:)``. Messages never contain tokens or camera data.
public struct Log: Sendable {
    private static let installedSink = OSAllocatedUnfairLock<(any LogSink)?>(initialState: nil)

    /// The component name written with every message.
    public let category: String

    private let sink: (any LogSink)?
    private let logger: Logger

    /// Creates a logger for a component.
    ///
    /// - Parameters:
    ///   - category: The component name written with every message.
    ///   - sink: A sink used instead of the installed one, for tests.
    public init(_ category: String, sink: (any LogSink)? = nil) {
        self.category = category
        self.sink = sink
        logger = Logger(subsystem: AppInfo.bundleIdentifier, category: category)
    }

    /// Installs the sink that receives the messages of all loggers without an own sink.
    ///
    /// - Parameter sink: The sink, typically a ``RotatingLogFile``.
    /// - Returns: `false` if a sink was installed before; the first one stays active.
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

    /// Writes a message.
    ///
    /// - Parameters:
    ///   - level: The severity.
    ///   - message: The message text.
    public func log(_ level: LogLevel, _ message: String) {
        logger.log(level: level.osLogType, "\(message, privacy: .public)")
        let target = sink ?? Log.installedSink.withLock { $0 }
        target?.write(level: level, category: category, message: message)
    }

    /// Writes a debug message.
    ///
    /// - Parameter message: The message text.
    public func debug(_ message: String) {
        log(.debug, message)
    }

    /// Writes an info message.
    ///
    /// - Parameter message: The message text.
    public func info(_ message: String) {
        log(.info, message)
    }

    /// Writes a warning.
    ///
    /// - Parameter message: The message text.
    public func warning(_ message: String) {
        log(.warning, message)
    }

    /// Writes an error message.
    ///
    /// - Parameter message: The message text.
    public func error(_ message: String) {
        log(.error, message)
    }

    /// Writes a critical message.
    ///
    /// - Parameter message: The message text.
    public func critical(_ message: String) {
        log(.critical, message)
    }
}
