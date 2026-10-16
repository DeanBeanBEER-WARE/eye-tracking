import Foundation
import Testing

@testable import CoreKit
@testable import UpdateKit

@Suite("Updater")
struct UpdateTests {
    private static let releaseText = """
        {
          "tag_name": "v0.1.7",
          "html_url": "https://github.com/o/r/releases/tag/v0.1.7",
          "assets": [
            {"name": "notes.txt", "url": "https://api/x/1", "browser_download_url": "https://x/notes.txt"},
            {"name": "EyeTracking-0.1.7.dmg", "url": "https://api/x/2", "browser_download_url": "https://x/a.dmg"},
            {"name": "EyeTracking-other.dmg", "url": "https://api/x/3", "browser_download_url": "https://x/b.dmg"}
          ]
        }
        """
    private static let release = JSONValue.parse(releaseText)

    @Test("No release is unavailable")
    func noRelease() {
        #expect(ReleaseEvaluator.evaluate(nil, current: "0.1.6").status == .unavailable)
        #expect(ReleaseEvaluator.evaluate(.object([:]), current: "0.1.6").status == .unavailable)
    }

    @Test("A newer tag is an update with version, URL, tag and the first app disk image")
    func newerTag() {
        let result = ReleaseEvaluator.evaluate(Self.release, current: "0.1.6")
        #expect(
            result
                == UpdateResult(
                    status: .update,
                    latest: "0.1.7",
                    url: "https://github.com/o/r/releases/tag/v0.1.7",
                    tag: "v0.1.7",
                    dmgURL: "https://x/a.dmg",
                    assetAPIURL: "https://api/x/2",
                    dmgName: "EyeTracking-0.1.7.dmg"
                ))
    }

    @Test("Only EyeTracking disk images are release images")
    func imageNames() {
        #expect(AppInfo.isImage(named: "EyeTracking-0.1.0.dmg"))
        #expect(!AppInfo.isImage(named: "WhisperAssistant-1.3.4.dmg"))
        #expect(!AppInfo.isImage(named: "EyeTracking-0.1.0.zip"))
    }

    @Test("An equal or older release is current")
    func equalVersion() {
        #expect(ReleaseEvaluator.evaluate(Self.release, current: "0.1.7").status == .current)
        #expect(ReleaseEvaluator.evaluate(Self.release, current: "0.1.7.0").status == .current)
        #expect(ReleaseEvaluator.evaluate(Self.release, current: "0.2").status == .current)
    }

    @Test("Fallbacks for name, URL and missing assets")
    func fallbacks() {
        let release = JSONValue.object(["tag_name": .string(""), "name": .string("Release 1.2")])
        let result = ReleaseEvaluator.evaluate(release, current: "1.1", repositorySlug: "o/r")
        #expect(result.status == .update)
        #expect(result.tag == "Release 1.2")
        #expect(result.latest == "1.2")
        #expect(result.url == "https://github.com/o/r/releases")
        #expect(result.dmgURL == "" && result.assetAPIURL == "")
    }

    @Test("An unparsable tag keeps the raw text and is not newer")
    func unparsableTag() {
        let result = ReleaseEvaluator.evaluate(.object(["tag_name": .string("nightly")]), current: "0.1.6")
        #expect(result.status == .current)
        #expect(result.latest == "nightly")
    }

    @Test("Version comparison")
    func versions() {
        #expect(VersionCompare.parse("v0.1.7") == [0, 1, 7])
        #expect(VersionCompare.parse("nightly").isEmpty)
        #expect(VersionCompare.isNewer("v0.1.10", than: "0.1.9"))
        #expect(!VersionCompare.isNewer("v0.1.9", than: "0.1.10"))
        #expect(VersionCompare.isNewer("1.0", than: "0.9.9"))
    }

    @Test("Silent checks every three hours notify once per release")
    func schedule() {
        #expect(UpdateSchedule.interval == 10800)
        let update = UpdateResult(status: .update, latest: "0.1.7")
        #expect(UpdateSchedule.shouldNotify(update, notified: ""))
        #expect(UpdateSchedule.shouldNotify(update, notified: "0.1.6"))
        #expect(!UpdateSchedule.shouldNotify(update, notified: "0.1.7"))
        #expect(!UpdateSchedule.shouldNotify(UpdateResult(status: .current, latest: "0.1.8"), notified: ""))
    }

    @Test("Update target rules")
    func updateTarget() {
        let all: (String) -> Bool = { _ in true }
        #expect(UpdateTarget.installable(bundlePath: "/usr/bin", isWritable: all) == nil)
        #expect(
            UpdateTarget.installable(bundlePath: "/private/var/AppTranslocation/1/d/E.app", isWritable: all) == nil)
        #expect(UpdateTarget.installable(bundlePath: "/Volumes/E/E.app", isWritable: all) == nil)
        #expect(
            UpdateTarget.installable(bundlePath: "/Applications/E.app", isWritable: { $0 != "/Applications/E.app" })
                == nil)
        #expect(
            UpdateTarget.installable(bundlePath: "/Applications/E.app", isWritable: { $0 != "/Applications" }) == nil)
        #expect(UpdateTarget.installable(bundlePath: "/Applications/E.app", isWritable: all) == "/Applications/E.app")
        #expect(UpdateTarget.installable(bundlePath: "/Applications/E.app/", isWritable: all) == "/Applications/E.app")
    }

    @Test("Swap script arguments and content")
    func script() {
        let arguments = UpdateScript.arguments(
            pid: 42, staged: "/w/staged/E.app", target: "/A/E.app", workDirectory: "/w")
        #expect(
            arguments == ["-c", UpdateScript.text, "eye-tracking-update", "42", "/w/staged/E.app", "/A/E.app", "/w"])
        #expect(UpdateScript.shell == "/bin/sh")
        #expect(UpdateScript.text.contains(#"while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 120 ]; do"#))
        #expect(UpdateScript.text.contains(#"mv "$backup" "$target""#))
        #expect(UpdateScript.text.contains(#"rm -rf "$workdir""#))
        #expect(UpdateScript.text.hasSuffix(#"/usr/bin/open "$target""#))
    }

    @Test("The check sends the token and evaluates the answer")
    func authenticatedCheck() async throws {
        let transport = FakeTransport([FakeTransport.json(Self.releaseText)])
        let result = await makeFetcher(transport, token: "t0k").check(current: "0.1.6")
        #expect(result.status == .update)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/o/r/releases/latest")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(request.timeoutInterval == 15)
    }

    @Test("Without a token the request is anonymous")
    func anonymousCheck() async throws {
        let transport = FakeTransport([FakeTransport.json(Self.releaseText)])
        let result = await makeFetcher(transport, token: nil).check(current: "0.1.7")
        #expect(result.status == .current)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A rejected token is retried once without it")
    func rejectedToken() async {
        let transport = FakeTransport([FakeTransport.json("{}", status: 401), FakeTransport.json(Self.releaseText)])
        let result = await makeFetcher(transport, token: "old").check(current: "0.1.6")
        #expect(result.status == .update)
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", nil])
    }

    @Test("404 is unavailable, other statuses and network errors are errors")
    func failures() async {
        let notFound = makeFetcher(FakeTransport([FakeTransport.json("{}", status: 404)]), token: "t")
        #expect(await notFound.check(current: "0.1.6").status == .unavailable)
        let offline = makeFetcher(FakeTransport([.failure(.notConnected)]), token: nil)
        #expect(
            await offline.check(current: "0.1.6")
                == UpdateResult(status: .error, message: "not connected to the internet"))
        let serverError = makeFetcher(FakeTransport([FakeTransport.json("{}", status: 500)]), token: nil)
        #expect(
            await serverError.check(current: "0.1.6")
                == UpdateResult(status: .error, message: "HTTP 500 from the GitHub API"))
    }

    @Test("The token of the configured account is preferred, the active account is the fallback")
    func githubToken() {
        let runner = FakeProcessRunner { _, arguments in
            arguments.contains("--user")
                ? ProcessOutput(exitCode: 1, stderr: "no account found")
                : ProcessOutput(exitCode: 0, stdout: "gho_active\n")
        }
        let auth = GitHubAuth(
            runner: runner, fileExists: { $0 == "/usr/local/bin/gh" }, account: "acc",
            log: Log("Test", sink: CaptureSink()))
        #expect(auth.ghPath == "/usr/local/bin/gh")
        #expect(auth.token() == "gho_active")
        #expect(
            runner.calls.map(\.arguments) == [["auth", "token", "--user", "acc"], ["auth", "token"]])
        #expect(runner.calls.allSatisfy { $0.executable == "/usr/local/bin/gh" && $0.timeout == 10 })

        let preferred = FakeProcessRunner { _, _ in ProcessOutput(exitCode: 0, stdout: "gho_user") }
        let direct = GitHubAuth(
            runner: preferred, fileExists: { _ in true }, account: "acc", log: Log("Test", sink: CaptureSink()))
        #expect(direct.token() == "gho_user")
        #expect(preferred.calls.count == 1)
    }

    @Test("Without gh there is no token and nothing runs")
    func noGitHubCLI() {
        let runner = FakeProcessRunner { _, _ in ProcessOutput(exitCode: 0, stdout: "x") }
        let auth = GitHubAuth(runner: runner, fileExists: { _ in false }, log: Log("Test", sink: CaptureSink()))
        #expect(auth.token() == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test("The token is dropped only on redirects to another host")
    func redirectGuard() throws {
        var request = URLRequest(url: try #require(URL(string: "https://api.github.com/repos/o/r/releases/assets/2")))
        request.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        let same = AssetDownloader.redirected(request, originalHost: "api.github.com")
        #expect(same.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        var storage = request
        storage.url = URL(string: "https://objects.githubusercontent.com/signed")
        let other = AssetDownloader.redirected(storage, originalHost: "api.github.com")
        #expect(other.value(forHTTPHeaderField: "Authorization") == nil)
    }

    private func makeFetcher(_ transport: FakeTransport, token: String?) -> ReleaseFetcher {
        ReleaseFetcher(
            transport: transport,
            token: { token },
            repositorySlug: "o/r",
            log: Log("Test", sink: CaptureSink())
        )
    }
}
