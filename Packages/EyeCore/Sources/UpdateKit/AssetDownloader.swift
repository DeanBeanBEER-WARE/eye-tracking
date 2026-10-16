import CoreKit
import Foundation

/// Downloads release assets with `URLSession`.
///
/// The asset API answers with a redirect to a pre-signed storage URL on another host; the token must not be sent
/// there, so the `Authorization` header is dropped on every redirect that leaves the original host.
public enum AssetDownloader {
    /// Downloads a request to a destination file.
    ///
    /// - Parameters:
    ///   - request: The download request, for example from ``UpdateInstaller/downloadRequest(for:token:)``.
    ///   - destination: The file to create.
    /// - Throws: ``HTTPTransportError`` for a failed transfer or a non-2xx status, or the file system error.
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

    /// Returns the request to follow a redirect with.
    ///
    /// - Parameters:
    ///   - request: The redirect request proposed by `URLSession`.
    ///   - originalHost: The host of the first request.
    /// - Returns: The request without `Authorization` if it leaves the original host, otherwise unchanged.
    public static func redirected(_ request: URLRequest, originalHost: String?) -> URLRequest {
        guard request.url?.host != originalHost else {
            return request
        }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}

/// Applies ``AssetDownloader/redirected(_:originalHost:)`` to every redirect of one download.
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
