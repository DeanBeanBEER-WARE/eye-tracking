import CoreKit
import Foundation

public enum UpdateInstallError: Error, Equatable, Sendable {
    case downloadFailed

    case mountFailed

    case noApp

    case copyFailed

    case invalidBundle

    case signatureFailed

    case launchFailed
}

public struct UpdateInstaller: Sendable {
    public static let downloadTimeout: TimeInterval = 300

    public static let toolTimeout: TimeInterval = 120

    public static let detachTimeout: TimeInterval = 60

    public static let hdiutil = "/usr/bin/hdiutil"

    public static let ditto = "/usr/bin/ditto"

    private let runner: any ProcessRunner
    private let token: @Sendable () -> String?
    private let download: @Sendable (URLRequest, URL) async throws -> Void
    private let spawn: @Sendable (String, [String]) throws -> Void
    private let temporaryDirectory: URL
    private let processIdentifier: Int32
    private let bundleIdentifier: String
    private let signatureCheck: (@Sendable (URL) -> Bool?)?
    private let log: Log

    public init(
        runner: any ProcessRunner,
        token: @escaping @Sendable () -> String?,
        download: @escaping @Sendable (URLRequest, URL) async throws -> Void,
        spawn: @escaping @Sendable (String, [String]) throws -> Void,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String = AppInfo.bundleIdentifier,
        signatureCheck: (@Sendable (URL) -> Bool?)? = nil,
        log: Log = Log("Updater")
    ) {
        self.runner = runner
        self.token = token
        self.download = download
        self.spawn = spawn
        self.temporaryDirectory = temporaryDirectory
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.signatureCheck = signatureCheck
        self.log = log
    }

    public static func downloadRequest(for result: UpdateResult, token: String?) -> URLRequest? {
        if let token, let url = URL(string: result.assetAPIURL), !result.assetAPIURL.isEmpty {
            var request = URLRequest(url: url, timeoutInterval: downloadTimeout)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        guard let url = URL(string: result.dmgURL), !result.dmgURL.isEmpty else {
            return nil
        }
        return URLRequest(url: url, timeoutInterval: downloadTimeout)
    }

    public func install(_ result: UpdateResult, target: String) async throws(UpdateInstallError) {
        let fileManager = FileManager.default
        let work = temporaryDirectory.appendingPathComponent(
            "eye-tracking-update-\(UUID().uuidString)", isDirectory: true)
        do throws(UpdateInstallError) {
            do {
                try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            } catch {
                log.error("Could not create the update work directory: \(error)")
                throw UpdateInstallError.launchFailed
            }
            let dmg = try await downloadImage(result, into: work)
            let staged = try await stage(dmg, in: work)
            let arguments = UpdateScript.arguments(
                pid: processIdentifier, staged: staged.path, target: target, workDirectory: work.path)
            do {
                try spawn(UpdateScript.shell, arguments)
            } catch {
                log.error("Could not start the update installer: \(error)")
                throw UpdateInstallError.launchFailed
            }
            log.info("Update installer started for \(target).")
        } catch {
            try? fileManager.removeItem(at: work)
            throw error
        }
    }

    public static func bundleIdentifier(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    private func downloadImage(_ result: UpdateResult, into work: URL) async throws(UpdateInstallError) -> URL {
        let token = result.needsAuthentication ? await Offload.run(token) : nil
        guard let request = Self.downloadRequest(for: result, token: token) else {
            log.warning("The release has no disk image to download.")
            throw UpdateInstallError.downloadFailed
        }
        let name = result.dmgName.isEmpty ? "\(AppInfo.imagePrefix)update.dmg" : result.dmgName
        let destination = work.appendingPathComponent((name as NSString).lastPathComponent)
        do {
            try await download(request, destination)
        } catch {
            log.warning("DMG download failed: \(error)")
            throw UpdateInstallError.downloadFailed
        }
        return destination
    }

    private func stage(_ dmg: URL, in work: URL) async throws(UpdateInstallError) -> URL {
        let mount = work.appendingPathComponent("mnt", isDirectory: true)
        let stagedDirectory = work.appendingPathComponent("staged", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
        } catch {
            log.error("Could not create the update directories: \(error)")
            throw UpdateInstallError.launchFailed
        }
        let attach = ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]
        guard await run(Self.hdiutil, attach, timeout: Self.toolTimeout, label: "hdiutil attach") else {
            throw UpdateInstallError.mountFailed
        }
        let staged: URL
        do throws(UpdateInstallError) {
            guard let source = firstApp(in: mount) else {
                throw UpdateInstallError.noApp
            }
            staged = stagedDirectory.appendingPathComponent(source.lastPathComponent)
            guard await run(Self.ditto, [source.path, staged.path], timeout: Self.toolTimeout, label: "ditto") else {
                throw UpdateInstallError.copyFailed
            }
        } catch {
            await detach(mount)
            throw error
        }
        await detach(mount)
        let identifier = Self.bundleIdentifier(of: staged)
        guard identifier == bundleIdentifier else {
            log.warning("The disk image holds \(identifier ?? "no bundle identifier") instead of the app.")
            throw UpdateInstallError.invalidBundle
        }
        if let valid = signatureCheck?(staged), !valid {
            log.warning("The staged app does not satisfy the code-signing requirement of the running app.")
            throw UpdateInstallError.signatureFailed
        }
        return staged
    }

    private func detach(_ mount: URL) async {
        _ = await run(
            Self.hdiutil, ["detach", mount.path, "-force"], timeout: Self.detachTimeout, label: "hdiutil detach")
    }

    private func firstApp(in directory: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let name = names.filter { ($0 as NSString).pathExtension == "app" }.min()
        return name.map { directory.appendingPathComponent($0) }
    }

    private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, label: String) async -> Bool {
        let runner = runner
        let result = await Offload.run {
            Result { try runner.run(executable, arguments: arguments, timeout: timeout) }
        }
        switch result {
        case .success(let output) where output.exitCode == 0:
            return true
        case .success(let output):
            log.warning("\(label) returned \(output.exitCode): \(TextLimits.excerpt(output.stderr, 300))")
            return false
        case .failure(let error):
            log.warning("\(label) failed: \(error)")
            return false
        }
    }
}
