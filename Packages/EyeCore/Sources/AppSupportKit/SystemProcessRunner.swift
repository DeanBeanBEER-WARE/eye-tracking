import CoreKit
import Foundation

/// Runs command line tools with `Process`, collecting their output and enforcing a timeout.
public struct SystemProcessRunner: ProcessRunner {
    private static let killGrace: TimeInterval = 2

    /// Creates the runner.
    public init() {}

    /// Runs an executable to completion and blocks the calling thread meanwhile.
    ///
    /// Standard input is `/dev/null`. After the timeout the process is terminated, and killed if it does not exit
    /// within two seconds.
    ///
    /// - Parameters:
    ///   - executable: The absolute path of the executable.
    ///   - arguments: The arguments.
    ///   - timeout: The maximum run time in seconds.
    /// - Returns: The exit status and the decoded output.
    /// - Throws: `ProcessRunnerError` if the process cannot start or times out.
    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
        let output = PipeReader(stdout)
        let errors = PipeReader(stderr)
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + Self.killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw ProcessRunnerError.timedOut
        }
        let deadline = DispatchTime.now() + Self.killGrace
        return ProcessOutput(
            exitCode: process.terminationStatus,
            stdout: output.text(waitingUntil: deadline),
            stderr: errors.text(waitingUntil: deadline)
        )
    }
}

/// Drains a pipe on a background queue so a chatty child never blocks on a full pipe buffer.
private final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    /// Starts reading the pipe until its end.
    ///
    /// - Parameter pipe: The pipe connected to the child's output.
    init(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            let read = handle.readDataToEndOfFile()
            self.lock.withLock { self.data = read }
            self.done.signal()
        }
    }

    /// Returns the output read so far, waiting for the end of the pipe up to a deadline.
    ///
    /// - Parameter deadline: The latest time to wait until.
    /// - Returns: The output decoded as UTF-8.
    func text(waitingUntil deadline: DispatchTime) -> String {
        _ = done.wait(timeout: deadline)
        return lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
