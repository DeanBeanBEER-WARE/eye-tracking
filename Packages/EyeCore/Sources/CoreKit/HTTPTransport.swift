import Foundation

/// A complete HTTP response.
public struct HTTPResponse: Equatable, Sendable {
    /// The HTTP status code.
    public var status: Int

    /// The response body.
    public var body: Data

    /// Creates a response.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - body: The response body.
    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// A transport failure where no complete response arrived.
public enum HTTPTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The server did not send data within the timeout.
    case timedOut

    /// The connection to the server could not be established.
    case cannotConnect

    /// The machine has no network connection.
    case notConnected

    /// The host name could not be resolved.
    case dnsFailure

    /// The request was cancelled.
    case cancelled

    /// Any other failure, with a description for the log.
    case other(String)

    /// A short description for the log.
    public var description: String {
        switch self {
        case .timedOut: "request timed out"
        case .cannotConnect: "cannot connect to host"
        case .notConnected: "not connected to the internet"
        case .dnsFailure: "host name lookup failed"
        case .cancelled: "request cancelled"
        case .other(let message): message
        }
    }
}

/// Sends HTTP requests, injectable for tests.
public protocol HTTPTransport: Sendable {
    /// Sends a request and reads the complete response.
    ///
    /// - Parameter request: The request.
    /// - Returns: The status and body; error statuses are returned, not thrown.
    /// - Throws: ``HTTPTransportError`` if no response arrived.
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
