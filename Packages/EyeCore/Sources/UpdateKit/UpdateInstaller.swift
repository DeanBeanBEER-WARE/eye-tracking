import CoreKit
import Foundation

/// A failed step of the update installation.
public enum UpdateInstallError: Error, Equatable, Sendable {
    /// No disk image could be downloaded.
    case downloadFailed

    /// The disk image could not be mounted.
    case mountFailed

    /// The disk image holds no app bundle.
    case noApp

    /// The app could not be copied out of the disk image.
    case copyFailed

    /// The app in the disk image is not Eye Tracking.
    case invalidBundle

    /// The staged app is not signed with the certificate of the installed app.
    case signatureFailed

    /// The swap script could not be started.
    case launchFailed
}

/// Downloads a release disk image, stages its app and starts the script that swaps the bundle after quit.
public struct UpdateInstaller: Sendable {
    /// The timeout of a download.
    public static let downloadTimeout: TimeInterval = 300

    /// The timeout of `hdiutil attach` and `ditto`.
    public static let toolTimeout: TimeInterval = 120

    /// The timeout of `hdiutil detach`.
    public static let detachTimeout: TimeInterval = 60

    /// The disk image tool.
    public static let hdiutil = "/usr/bin/hdiutil"

    /// The copy tool that keeps bundle metadata.
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

    /// Creates the installer.
    ///
    /// - Parameters:
    ///   - runner: Runs `hdiutil` and `ditto`.
    ///   - token: Returns the GitHub token for the private asset, or `nil`; may block.
    ///   - download: Downloads a request to a destination file.
    ///   - spawn: Starts the detached swap script with an executable and its arguments.
    ///   - temporaryDirectory: The directory the work directory is created in.
    ///   - processIdentifier: The process the swap script waits for.
    ///   - bundleIdentifier: The bundle identifier the staged app must have.
    ///   - signatureCheck: Validates a staged bundle against the code-signing requirement of the running app;
    ///     `nil` as result skips the check (an unsigned running app, for example a Debug build), `false` rejects
    ///     the bundle.
    ///   - log: The logger.
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

    /// The request that downloads the disk image of a release.
    ///
    /// With a token the asset API URL is used (the only way to reach assets of a private repository); without one
    /// the browser download URL.
    ///
    /// - Parameters:
    ///   - result: The update result of the release.
    ///   - token: The GitHub token, or `nil`.
    /// - Returns: The request, or `nil` if the release has no usable disk image URL.
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

    /// Downloads and stages the release and starts the swap script; the caller must quit afterwards.
    ///
    /// The work directory is removed on failure; on success the script removes it.
    ///
    /// - Parameters:
    ///   - result: The update result of the release.
    ///   - target: The installed app bundle to replace.
    /// - Throws: `UpdateInstallError` for the failed step.
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

    /// Reads the bundle identifier of an app bundle.
    ///
    /// - Parameter app: The app bundle.
    /// - Returns: The `CFBundleIdentifier` of its `Info.plist`, or `nil` if it cannot be read.
    public static func bundleIdentifier(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    private func downloadImage(_ result: UpdateResult, into work: URL) async throws(UpdateInstallError) -> URL {
        let token = await Offload.run(token)
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
        // Names instead of listed URLs keep every path under `directory` as given (listing resolves /var symlinks).
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let name = names.filter { ($0 as NSString).pathExtension == "app" }.min()
        return name.map { directory.appendingPathComponent($0) }
    }

    /// Runs a tool off the cooperative pool.
    ///
    /// - Returns: `true` if the tool exited with status 0.
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
