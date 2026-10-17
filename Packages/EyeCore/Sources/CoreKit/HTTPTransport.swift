import Foundation

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int

    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

public enum HTTPTransportError: Error, Equatable, Sendable, CustomStringConvertible {
    case timedOut

    case cannotConnect

    case notConnected

    case dnsFailure

    case cancelled

    case other(String)

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

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
