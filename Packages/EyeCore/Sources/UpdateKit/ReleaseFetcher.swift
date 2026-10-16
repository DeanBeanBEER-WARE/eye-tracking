import CoreKit
import Foundation

/// Fetches the latest GitHub release of the private repository.
///
/// The request carries the token from ``GitHubAuth`` when one is available; a rejected token (401) is retried once
/// without it. A 404 means the release information is not reachable (no access, or no release yet).
public struct ReleaseFetcher: Sendable {
    /// The timeout of the API call.
    public static let apiTimeout: TimeInterval = 15

    private let transport: any HTTPTransport
    private let token: @Sendable () -> String?
    private let repositorySlug: String
    private let log: Log

    /// Creates the fetcher.
    ///
    /// - Parameters:
    ///   - transport: The HTTP transport of the API call.
    ///   - token: Returns the GitHub token, or `nil`; may block, it runs on a background queue.
    ///   - repositorySlug: The repository to query.
    ///   - log: The logger.
    public init(
        transport: any HTTPTransport,
        token: @escaping @Sendable () -> String?,
        repositorySlug: String = AppInfo.repositorySlug,
        log: Log = Log("Updater")
    ) {
        self.transport = transport
        self.token = token
        self.repositorySlug = repositorySlug
        self.log = log
    }

    /// The API request for the latest release.
    ///
    /// - Parameter token: The GitHub token, or `nil` for an anonymous request.
    /// - Returns: The request, or `nil` if the repository slug forms no valid URL.
    public func request(token: String?) -> URLRequest? {
        guard let url = URL(string: "https://api.github.com/repos/\(repositorySlug)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: ReleaseFetcher.apiTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Checks for a newer release; never throws.
    ///
    /// - Parameter current: The installed version.
    /// - Returns: The update result.
    public func check(current: String) async -> UpdateResult {
        let token = await Offload.run(token)
        do {
            var response = try await fetch(token: token)
            if token != nil, response.status == 401 {
                log.warning("The GitHub token was rejected; retrying without it.")
                response = try await fetch(token: nil)
            }
            switch response.status {
            case 200..<300:
                let release = JSONValue.parse(response.body).flatMap { $0.objectValue == nil ? nil : $0 }
                let result = ReleaseEvaluator.evaluate(release, current: current, repositorySlug: repositorySlug)
                log.info("Update check: \(result.status.rawValue) (latest=\(result.latest)).")
                return result
            case 404:
                log.info("Update check: no release reachable (token: \(token == nil ? "none" : "present")).")
                return UpdateResult(status: .unavailable)
            default:
                return UpdateResult(status: .error, message: "HTTP \(response.status) from the GitHub API")
            }
        } catch {
            log.warning("Update check failed: \(error)")
            return UpdateResult(status: .error, message: String(describing: error))
        }
    }

    private func fetch(token: String?) async throws -> HTTPResponse {
        guard let request = request(token: token) else {
            throw HTTPTransportError.other("invalid repository slug \(repositorySlug)")
        }
        return try await transport.send(request)
    }
}

/// Runs blocking work on a global queue so it never holds a thread of the cooperative pool.
enum Offload {
    /// Runs a blocking closure and returns its result.
    ///
    /// - Parameter work: The blocking work.
    /// - Returns: The result of the work.
    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }
}
