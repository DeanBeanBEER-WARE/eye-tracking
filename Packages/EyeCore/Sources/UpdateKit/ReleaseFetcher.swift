import CoreKit
import Foundation

public struct ReleaseFetcher: Sendable {
    public static let apiTimeout: TimeInterval = 15

    private let transport: any HTTPTransport
    private let token: @Sendable () -> String?
    private let repositorySlug: String
    private let log: Log

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

    public func check(current: String) async -> UpdateResult {
        do {
            var response = try await fetch(token: nil)
            var authenticated = false
            if response.status == 404, let token = await Offload.run(token) {
                log.info("The release is not public; retrying with the GitHub CLI token.")
                response = try await fetch(token: token)
                authenticated = true
            }
            switch response.status {
            case 200..<300:
                let release = JSONValue.parse(response.body).flatMap { $0.objectValue == nil ? nil : $0 }
                var result = ReleaseEvaluator.evaluate(release, current: current, repositorySlug: repositorySlug)
                result.needsAuthentication = authenticated
                log.info("Update check: \(result.status.rawValue) (latest=\(result.latest)).")
                return result
            case 401, 404:
                log.info("Update check: no release reachable (token: \(authenticated ? "used" : "none")).")
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

enum Offload {
    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }
}
