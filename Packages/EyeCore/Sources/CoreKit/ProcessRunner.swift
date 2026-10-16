import Foundation

/// The result of a finished child process.
public struct ProcessOutput: Equatable, Sendable {
    /// The exit status.
    public var exitCode: Int32

    /// The standard output, decoded as UTF-8.
    public var stdout: String

    /// The standard error, decoded as UTF-8.
    public var stderr: String

    /// Creates a process result.
    ///
    /// - Parameters:
    ///   - exitCode: The exit status.
    ///   - stdout: The standard output.
    ///   - stderr: The standard error.
    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// A child process that could not run to completion.
public enum ProcessRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The executable could not be started.
    case launchFailed(String)

    /// The process did not finish in time and was terminated.
    case timedOut

    /// A short description for the log.
    public var description: String {
        switch self {
        case .launchFailed(let message): "launch failed: \(message)"
        case .timedOut: "timed out"
        }
    }
}

/// Runs executables without a shell, implemented with `Process` by the app and faked in tests.
public protocol ProcessRunner: Sendable {
    /// Runs an executable and waits for it to exit.
    ///
    /// - Parameters:
    ///   - executable: The absolute path of the executable.
    ///   - arguments: The arguments, passed without shell interpretation.
    ///   - timeout: The seconds after which the process is terminated.
    /// - Returns: The exit status and the captured output.
    /// - Throws: ``ProcessRunnerError`` if the process cannot start or times out.
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput
}
