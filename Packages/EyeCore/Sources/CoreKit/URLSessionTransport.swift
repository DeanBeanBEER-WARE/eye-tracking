import Foundation

public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch {
            throw URLSessionTransport.map(error)
        }
    }

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
