import CoreKit
import Foundation
import UserNotifications

/// Posts user notifications with the app name as title.
///
/// Authorization is requested with the first notification; a denial is logged once.
@MainActor
public final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let log = Log("Notifier")
    private var authorization: Task<Bool, Never>?
    private var loggedDenial = false

    /// Creates the notifier and shows its notifications also while the app is active.
    override public init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Posts a notification.
    ///
    /// - Parameters:
    ///   - subtitle: The subtitle, for example "Update verfügbar".
    ///   - message: The message text.
    public func post(subtitle: String, message: String) {
        let request = Self.request(subtitle: subtitle, message: message)
        let authorization = authorization ?? makeAuthorization()
        Task {
            guard await authorization.value else {
                logDenialOnce()
                return
            }
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                log.error("Notification could not be posted: \(error)")
            }
        }
    }

    /// Shows banners also while a window of the app is in front.
    ///
    /// - Parameters:
    ///   - center: The notification center.
    ///   - notification: The notification about to be shown.
    /// - Returns: The presentation options.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    private func makeAuthorization() -> Task<Bool, Never> {
        let log = log
        let task = Task<Bool, Never> {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                log.error("Notification authorization failed: \(error)")
                return false
            }
        }
        authorization = task
        return task
    }

    private func logDenialOnce() {
        guard !loggedDenial else {
            return
        }
        loggedDenial = true
        log.warning("Notifications are not allowed; enable them in System Settings > Notifications.")
    }

    private nonisolated static func request(subtitle: String, message: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = AppInfo.displayName
        content.subtitle = subtitle
        content.body = message
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }
}
