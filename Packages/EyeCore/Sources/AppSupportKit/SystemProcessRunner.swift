import CoreKit
import Foundation

public struct SystemProcessRunner: ProcessRunner {
    private static let killGrace: TimeInterval = 2

    public init() {}

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

private final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            let read = handle.readDataToEndOfFile()
            self.lock.withLock { self.data = read }
            self.done.signal()
        }
    }

    func text(waitingUntil deadline: DispatchTime) -> String {
        _ = done.wait(timeout: deadline)
        return lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
