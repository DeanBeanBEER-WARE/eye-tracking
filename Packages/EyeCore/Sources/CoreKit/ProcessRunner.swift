import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public var exitCode: Int32

    public var stdout: String

    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ProcessRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
    case launchFailed(String)

    case timedOut

    public var description: String {
        switch self {
        case .launchFailed(let message): "launch failed: \(message)"
        case .timedOut: "timed out"
        }
    }
}

public protocol ProcessRunner: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput
}
