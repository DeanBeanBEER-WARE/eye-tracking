import Foundation

/// The transport of the application, built on an ephemeral `URLSession` (no cache, no cookies).
public struct URLSessionTransport: HTTPTransport {
    /// The session used for all requests.
    public let session: URLSession

    /// Creates a transport.
    ///
    /// - Parameter session: The session used for all requests; the default is an ephemeral session.
    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    /// Sends a request and reads the complete response.
    ///
    /// - Parameter request: The request.
    /// - Returns: The status and body.
    /// - Throws: ``HTTPTransportError`` if no response arrived.
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch {
            throw URLSessionTransport.map(error)
        }
    }

    /// Maps a `URLSession` error to a transport error.
    ///
    /// - Parameter error: The error thrown by `URLSession`.
    /// - Returns: The matching transport error.
    public static func map(_ error: any Error) -> HTTPTransportError {
        if let error = error as? HTTPTransportError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        guard let urlError = error as? URLError else {
            return .other(String(describing: error))
        }
        switch urlError.code {
        case .timedOut:
            return .timedOut
        case .cannotConnectToHost:
            return .cannotConnect
        case .notConnectedToInternet:
            return .notConnected
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsFailure
        case .cancelled:
            return .cancelled
        default:
            return .other("URL error \(urlError.code.rawValue): \(urlError.localizedDescription)")
        }
    }
}
