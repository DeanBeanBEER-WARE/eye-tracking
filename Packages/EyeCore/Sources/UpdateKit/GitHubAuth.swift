import CoreKit
import Foundation

/// Reads a GitHub token from the GitHub CLI so the updater can reach the private repository.
///
/// The token of ``AppInfo/githubAccount`` is asked for explicitly (`gh auth token --user`), so the check works even
/// when another `gh` account is active; the active account is the fallback.
public struct GitHubAuth: Sendable {
    /// The locations searched for the GitHub CLI.
    public static let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    /// The timeout of one `gh auth token` call.
    public static let timeout: TimeInterval = 10

    private let runner: any ProcessRunner
    private let fileExists: @Sendable (String) -> Bool
    private let account: String
    private let log: Log

    /// Creates the token reader.
    ///
    /// - Parameters:
    ///   - runner: Runs the GitHub CLI.
    ///   - fileExists: Checks whether a GitHub CLI candidate exists.
    ///   - account: The account whose token is preferred.
    ///   - log: The logger.
    public init(
        runner: any ProcessRunner,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        account: String = AppInfo.githubAccount,
        log: Log = Log("Updater")
    ) {
        self.runner = runner
        self.fileExists = fileExists
        self.account = account
        self.log = log
    }

    /// The path of the GitHub CLI, or `nil` if it is not installed.
    public var ghPath: String? {
        GitHubAuth.ghCandidates.first { fileExists($0) }
    }

    /// Returns a token, preferring the configured account; blocks while `gh` runs.
    ///
    /// - Returns: The token, or `nil` without a GitHub CLI or a logged-in account.
    public func token() -> String? {
        guard let gh = ghPath else {
            log.info("GitHub CLI not found; the update check runs without a token.")
            return nil
        }
        if let token = read(gh, ["auth", "token", "--user", account]) {
            return token
        }
        log.info("No gh token for \(account); trying the active gh account.")
        return read(gh, ["auth", "token"])
    }

    private func read(_ gh: String, _ arguments: [String]) -> String? {
        do {
            let output = try runner.run(gh, arguments: arguments, timeout: GitHubAuth.timeout)
            let token = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard output.exitCode == 0, !token.isEmpty else {
                log.info(
                    "gh \(arguments.joined(separator: " ")) returned \(output.exitCode): "
                        + TextLimits.excerpt(output.stderr, 200))
                return nil
            }
            return token
        } catch {
            log.warning("gh \(arguments.joined(separator: " ")) failed: \(error)")
            return nil
        }
    }
}
