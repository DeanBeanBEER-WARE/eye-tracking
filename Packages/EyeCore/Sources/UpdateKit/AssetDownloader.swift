import CoreKit
import Foundation

public enum AssetDownloader {
    public static func download(_ request: URLRequest, to destination: URL) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let delegate = RedirectGuard(originalHost: request.url?.host)
        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await session.download(for: request, delegate: delegate)
        } catch {
            throw URLSessionTransport.map(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: temporary)
            throw HTTPTransportError.other("HTTP \(status) while downloading the release")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    public static func redirected(_ request: URLRequest, originalHost: String?) -> URLRequest {
        guard request.url?.host != originalHost else {
            return request
        }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let originalHost: String?

    init(originalHost: String?) {
        self.originalHost = originalHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        AssetDownloader.redirected(request, originalHost: originalHost)
    }
}
