import Foundation
import os

public final class RotatingLogFile: LogSink {
    public static let defaultFileName = "eye_tracking.log"

    public static let defaultMaxBytes = 5 * 1024 * 1024

    public static let defaultBackupCount = 3

    public let fileURL: URL

    public let maxBytes: Int

    public let backupCount: Int

    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let lock = OSAllocatedUnfairLock()

    public init(
        directory: URL,
        fallbackDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(AppInfo.directoryName),
        fileName: String = RotatingLogFile.defaultFileName,
        maxBytes: Int = RotatingLogFile.defaultMaxBytes,
        backupCount: Int = RotatingLogFile.defaultBackupCount,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let resolved = RotatingLogFile.isWritable(directory) ? directory : fallbackDirectory
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        fileURL = resolved.appendingPathComponent(fileName)
        self.maxBytes = maxBytes
        self.backupCount = backupCount
        self.timeZone = timeZone
        self.now = now
    }

    public func backupURL(_ index: Int) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("\(fileURL.lastPathComponent).\(index)")
    }

    public func write(level: LogLevel, category: String, message: String) {
        let line = RotatingLogFile.formatLine(
            date: now(),
            level: level,
            category: category,
            message: message,
            timeZone: timeZone
        )
        let data = Data(line.utf8)
        lock.withLock {
            let size = currentSize()
            if maxBytes > 0, size > 0, size + data.count >= maxBytes {
                rotate()
            }
            append(data)
        }
    }

    public static func formatLine(
        date: Date,
        level: LogLevel,
        category: String,
        message: String,
        timeZone: TimeZone
    ) -> String {
        let interval = date.timeIntervalSince1970
        let seconds = interval.rounded(.down)
        let milliseconds = min(999, Int((interval - seconds) * 1000))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: seconds)
        )
        let timestamp = String(
            format: "%04d-%02d-%02d %02d:%02d:%02d,%03d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0,
            milliseconds
        )
        let padded = level.name.padding(toLength: max(8, level.name.count), withPad: " ", startingAt: 0)
        return "\(timestamp) [\(padded)] \(category): \(message)\n"
    }

    private static func isWritable(_ directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appendingPathComponent(".write_test")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private func currentSize() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() {
        let manager = FileManager.default
        guard backupCount > 0 else {
            try? Data().write(to: fileURL)
            return
        }
        for index in stride(from: backupCount - 1, through: 1, by: -1) {
            let source = backupURL(index)
            guard manager.fileExists(atPath: source.path) else {
                continue
            }
            let target = backupURL(index + 1)
            try? manager.removeItem(at: target)
            try? manager.moveItem(at: source, to: target)
        }
        let first = backupURL(1)
        try? manager.removeItem(at: first)
        try? manager.moveItem(at: fileURL, to: first)
    }

    private func append(_ data: Data) {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
