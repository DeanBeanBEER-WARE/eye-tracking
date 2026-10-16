import Foundation
import os

@testable import CoreKit

/// A value guarded by a lock, for state shared with `@Sendable` closures.
final class Locked<Value: Sendable>: Sendable {
    private let storage: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        storage = OSAllocatedUnfairLock(initialState: value)
    }

    var value: Value {
        storage.withLock { $0 }
    }

    func mutate(_ change: @Sendable (inout Value) -> Void) {
        storage.withLock { change(&$0) }
    }
}

/// A transport that replays scripted replies and records the requests.
final class FakeTransport: HTTPTransport {
    enum Reply: Sendable {
        case response(HTTPResponse)
        case failure(HTTPTransportError)
    }

    private struct State {
        var replies: [Reply]
        var requests: [URLRequest] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(_ replies: [Reply]) {
        state = OSAllocatedUnfairLock(initialState: State(replies: replies))
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    static func json(_ text: String, status: Int = 200) -> Reply {
        .response(HTTPResponse(status: status, body: Data(text.utf8)))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let reply = state.withLock { state -> Reply in
            state.requests.append(request)
            return state.replies.isEmpty ? .failure(.other("no scripted reply")) : state.replies.removeFirst()
        }
        switch reply {
        case .response(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

/// A log sink that keeps every message.
final class CaptureSink: LogSink {
    struct Entry: Equatable, Sendable {
        var level: LogLevel
        var category: String
        var message: String
    }

    private let storage = Locked<[Entry]>([])

    var entries: [Entry] {
        storage.value
    }

    func write(level: LogLevel, category: String, message: String) {
        storage.mutate { $0.append(Entry(level: level, category: category, message: message)) }
    }
}

/// A process runner that answers from a closure and records every call.
final class FakeProcessRunner: ProcessRunner {
    struct Call: Equatable, Sendable {
        var executable: String
        var arguments: [String]
        var timeout: TimeInterval
    }

    private let handler: @Sendable (String, [String]) throws -> ProcessOutput
    private let storage = Locked<[Call]>([])

    init(_ handler: @escaping @Sendable (String, [String]) throws -> ProcessOutput) {
        self.handler = handler
    }

    var calls: [Call] {
        storage.value
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput {
        storage.mutate { $0.append(Call(executable: executable, arguments: arguments, timeout: timeout)) }
        return try handler(executable, arguments)
    }
}

/// Creates an empty temporary directory; the caller removes it.
func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "eyecore-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
