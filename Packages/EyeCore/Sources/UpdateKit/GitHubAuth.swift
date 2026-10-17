import CoreKit
import Foundation

public struct GitHubAuth: Sendable {
    public static let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    public static let timeout: TimeInterval = 10

    private let runner: any ProcessRunner
    private let fileExists: @Sendable (String) -> Bool
    private let account: String
    private let log: Log

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

    public var ghPath: String? {
        GitHubAuth.ghCandidates.first { fileExists($0) }
    }

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
