import AppKit
import AppSupportKit
import CoreKit
import UpdateKit

@MainActor
final class Updater {
    private let settings: SettingsStore
    private let notifier: Notifier
    private let fetcher: ReleaseFetcher
    private let installer: UpdateInstaller
    private let log = Log("Updater")
    private var scheduleTask: Task<Void, Never>?
    private var isInstalling = false
    private var available: UpdateResult?

    private(set) var isChecking = false

    var availableUpdate: String? {
        available?.latest
    }

    init(settings: SettingsStore, notifier: Notifier) {
        let runner = SystemProcessRunner()
        let auth = GitHubAuth(runner: runner)
        self.settings = settings
        self.notifier = notifier
        fetcher = ReleaseFetcher(transport: URLSessionTransport(), token: { auth.token() })
        installer = UpdateInstaller.system(runner: runner, token: { auth.token() })
    }

    func start() {
        runCheck(manual: false)
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UpdateSchedule.interval))
                guard !Task.isCancelled else { break }
                self?.runCheck(manual: false)
            }
        }
    }

    func stop() {
        scheduleTask?.cancel()
        scheduleTask = nil
    }

    func checkManually() {
        runCheck(manual: true)
    }

    func installAvailable() {
        guard let available else {
            checkManually()
            return
        }
        install(available)
    }

    private func runCheck(manual: Bool) {
        guard !isChecking else {
            return
        }
        isChecking = true
        let fetcher = fetcher
        let current = AppVersion.current
        Task {
            let result = await Task.detached { await fetcher.check(current: current) }.value
            isChecking = false
            show(result, manual: manual)
        }
    }

    private func show(_ result: UpdateResult, manual: Bool) {
        if result.status == .update {
            available = result
        } else if result.status == .current {
            available = nil
        }
        switch (result.status, manual) {
        case (.update, true):
            let message = String(localized: "update.available.message \(result.latest) \(AppVersion.current)")
            if Alerts.choose(
                String(localized: "update.available.title"),
                message,
                primary: String(localized: "update.button.update"),
                secondary: String(localized: "update.button.later")
            ) {
                install(result)
            }
        case (.update, false):
            notifyOnce(result)
        case (.current, true):
            Alerts.info(
                String(localized: "update.current.title"),
                String(localized: "update.current.message \(AppVersion.current)")
            )
        case (.unavailable, true):
            Alerts.info(String(localized: "update.check_failed.title"), String(localized: "update.unavailable.message"))
        case (.error, true):
            let message = result.message.isEmpty ? String(localized: "update.unknown_error") : result.message
            Alerts.info(String(localized: "update.check_failed.title"), message)
        default:
            log.info("Silent update check: \(result.status.rawValue) \(result.message)")
        }
    }

    private func notifyOnce(_ result: UpdateResult) {
        guard UpdateSchedule.shouldNotify(result, notified: settings.load().notifiedUpdate) else {
            return
        }
        notifier.post(
            subtitle: String(localized: "update.available.title"),
            message: String(localized: "update.available.notification \(result.latest)")
        )
        do {
            try settings.update { $0.notifiedUpdate = result.latest }
        } catch {
            log.error("Could not save the announced release: \(error)")
        }
    }

    private func install(_ result: UpdateResult) {
        let fileManager = FileManager.default
        guard
            let target = UpdateTarget.installable(
                bundlePath: Bundle.main.bundlePath,
                isWritable: { fileManager.isWritableFile(atPath: $0) }
            )
        else {
            log.info("Self-update not possible from \(Bundle.main.bundlePath); opening the release page.")
            openReleasePage(result)
            return
        }
        guard !isInstalling else {
            return
        }
        isInstalling = true
        notifier.post(
            subtitle: String(localized: "update.download.title"),
            message: String(localized: "update.download.message \(result.latest)")
        )
        let installer = installer
        Task {
            do {
                try await Task.detached { try await installer.install(result, target: target) }.value
                log.info("Update \(result.latest) staged; quitting for the install.")
                NSApp.terminate(nil)
            } catch {
                isInstalling = false
                let message = (error as? UpdateInstallError)?.message ?? String(localized: "update.unknown_error")
                if Alerts.choose(
                    String(localized: "update.failed.title"),
                    message,
                    primary: String(localized: "update.button.open_release"),
                    secondary: String(localized: "update.button.close")
                ) {
                    openReleasePage(result)
                }
            }
        }
    }

    private func openReleasePage(_ result: UpdateResult) {
        guard let url = URL(string: result.url), !result.url.isEmpty else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
