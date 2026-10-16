import Foundation
import Testing

@testable import CoreKit
@testable import UpdateKit

@Suite("Update installer")
struct UpdateInstallerTests {
    /// How the fake tools behave.
    struct Behavior: Sendable {
        var downloadSucceeds = true
        var attachSucceeds = true
        var appInImage = true
        var bundleIdentifier = "com.deanbean.eyetracking"
        var dittoSucceeds = true
        var signatureResult: Bool? = nil
    }

    /// What one installation did.
    struct Outcome {
        var error: UpdateInstallError?
        var calls: [FakeProcessRunner.Call]
        var spawned: [[String]]
        var downloads: [URLRequest]
        var leftovers: [String]
    }

    private static let release = UpdateResult(
        status: .update, latest: "0.1.7", url: "https://x/r", tag: "v0.1.7", dmgURL: "https://x/E-0.1.7.dmg",
        assetAPIURL: "https://api.github.com/repos/o/r/releases/assets/7", dmgName: "EyeTracking-0.1.7.dmg")

    private static func writeApp(at app: URL, identifier: String) throws {
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private static func value(after flag: String, in arguments: [String]) -> URL {
        URL(fileURLWithPath: arguments[(arguments.firstIndex(of: flag) ?? 0) + 1])
    }

    private func install(
        _ behavior: Behavior,
        token: String? = "t0k",
        release: UpdateResult = UpdateInstallerTests.release,
        spawnFails: Bool = false,
        signatureCheck: (@Sendable (URL) -> Bool?)? = nil
    ) async throws -> Outcome {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = FakeProcessRunner { executable, arguments in
            switch (executable, arguments.first) {
            case (_, "attach"):
                guard behavior.attachSucceeds else {
                    return ProcessOutput(exitCode: 1, stderr: "corrupt image")
                }
                if behavior.appInImage {
                    let mount = Self.value(after: "-mountpoint", in: arguments)
                    try Self.writeApp(
                        at: mount.appendingPathComponent("Eye Tracking.app"), identifier: behavior.bundleIdentifier)
                }
            case ("/usr/bin/ditto", _):
                guard behavior.dittoSucceeds else {
                    return ProcessOutput(exitCode: 1)
                }
                try FileManager.default.copyItem(atPath: arguments[0], toPath: arguments[1])
            default:
                break
            }
            return ProcessOutput(exitCode: 0)
        }
        let spawned = Locked<[[String]]>([])
        let downloads = Locked<[URLRequest]>([])
        let installer = UpdateInstaller(
            runner: runner,
            token: { token },
            download: { request, destination in
                downloads.mutate { $0.append(request) }
                guard behavior.downloadSucceeds else {
                    throw HTTPTransportError.other("HTTP 404 while downloading the release")
                }
                try Data("dmg".utf8).write(to: destination)
            },
            spawn: { executable, arguments in
                if spawnFails {
                    throw ProcessRunnerError.launchFailed("no such file")
                }
                spawned.mutate { $0.append([executable] + arguments) }
            },
            temporaryDirectory: root,
            processIdentifier: 42,
            signatureCheck: signatureCheck ?? { _ in behavior.signatureResult },
            log: Log("Test", sink: CaptureSink())
        )
        var error: UpdateInstallError?
        do {
            try await installer.install(release, target: "/Applications/Eye Tracking.app")
        } catch let failure {
            error = failure
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        return Outcome(
            error: error, calls: runner.calls, spawned: spawned.value, downloads: downloads.value, leftovers: leftovers)
    }

    @Test("A valid release is downloaded through the asset API, staged and handed to the swap script")
    func success() async throws {
        let outcome = try await install(Behavior())
        #expect(outcome.error == nil)
        #expect(outcome.leftovers.count == 1)
        let request = try #require(outcome.downloads.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/o/r/releases/assets/7")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(request.timeoutInterval == 300)
        let work = try #require(outcome.spawned.first?.last)
        #expect(outcome.calls.map(\.arguments.first) == ["attach", "\(work)/mnt/Eye Tracking.app", "detach"])
        #expect(
            outcome.calls[0].arguments == [
                "attach", "\(work)/EyeTracking-0.1.7.dmg", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint",
                "\(work)/mnt",
            ])
        #expect(outcome.calls[2].arguments == ["detach", "\(work)/mnt", "-force"])
        #expect(
            outcome.spawned == [
                ["/bin/sh"]
                    + UpdateScript.arguments(
                        pid: 42, staged: "\(work)/staged/Eye Tracking.app", target: "/Applications/Eye Tracking.app",
                        workDirectory: work)
            ])
    }

    @Test("Without a token the browser download URL is used")
    func anonymousDownload() async throws {
        let outcome = try await install(Behavior(), token: nil)
        #expect(outcome.error == nil)
        let request = try #require(outcome.downloads.first)
        #expect(request.url?.absoluteString == "https://x/E-0.1.7.dmg")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("No download source or a failed download fails and removes the work directory")
    func downloadFailure() async throws {
        var release = Self.release
        release.assetAPIURL = ""
        release.dmgURL = ""
        let noSource = try await install(Behavior(), release: release)
        #expect(noSource.error == .downloadFailed)
        #expect(noSource.downloads.isEmpty)
        #expect(noSource.leftovers.isEmpty)
        let failed = try await install(Behavior(downloadSucceeds: false))
        #expect(failed.error == .downloadFailed)
        #expect(failed.leftovers.isEmpty)
        #expect(failed.spawned.isEmpty)
    }

    @Test("A disk image that does not mount fails without detaching")
    func mountFailure() async throws {
        let outcome = try await install(Behavior(attachSucceeds: false))
        #expect(outcome.error == .mountFailed)
        #expect(!outcome.calls.contains { $0.arguments.first == "detach" })
        #expect(outcome.leftovers.isEmpty)
    }

    @Test("A disk image without an app or with a failed copy is detached and cleaned up")
    func stagingFailures() async throws {
        let noApp = try await install(Behavior(appInImage: false))
        #expect(noApp.error == .noApp)
        #expect(noApp.calls.last?.arguments.first == "detach")
        #expect(noApp.leftovers.isEmpty)
        let copy = try await install(Behavior(dittoSucceeds: false))
        #expect(copy.error == .copyFailed)
        #expect(copy.calls.last?.arguments.first == "detach")
        #expect(copy.leftovers.isEmpty)
    }

    @Test("An app with another bundle identifier is rejected")
    func bundleIdentifierCheck() async throws {
        let outcome = try await install(Behavior(bundleIdentifier: "com.whisperapp.assistant"))
        #expect(outcome.error == .invalidBundle)
        #expect(outcome.spawned.isEmpty)
        #expect(outcome.leftovers.isEmpty)
    }

    @Test("A staged app that fails the signature check is rejected; a skipped or passing check installs")
    func signature() async throws {
        let failed = try await install(Behavior(), signatureCheck: { _ in false })
        #expect(failed.error == .signatureFailed)
        #expect(failed.spawned.isEmpty)
        #expect(failed.leftovers.isEmpty)
        let skipped = try await install(Behavior(), signatureCheck: { _ in nil })
        #expect(skipped.error == nil && skipped.spawned.count == 1)
        let passed = try await install(Behavior(), signatureCheck: { _ in true })
        #expect(passed.error == nil && passed.spawned.count == 1)
    }

    @Test("A swap script that cannot start fails and cleans up")
    func spawnFailure() async throws {
        let outcome = try await install(Behavior(), spawnFails: true)
        #expect(outcome.error == .launchFailed)
        #expect(outcome.leftovers.isEmpty)
    }

    @Test("The bundle identifier is read from the Info.plist")
    func readsBundleIdentifier() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("A.app")
        #expect(UpdateInstaller.bundleIdentifier(of: app) == nil)
        try Self.writeApp(at: app, identifier: "com.example.a")
        #expect(UpdateInstaller.bundleIdentifier(of: app) == "com.example.a")
    }
}
