import CoreKit
import Foundation

/// The outcome of an update check.
public enum UpdateStatus: String, Equatable, Sendable {
    /// A newer release exists.
    case update

    /// The installed version is the latest release.
    case current

    /// The release information cannot be reached (private repository without a usable token).
    case unavailable

    /// The check failed with an error.
    case error
}

/// The result of an update check.
public struct UpdateResult: Equatable, Sendable {
    /// The outcome.
    public var status: UpdateStatus

    /// The display version of the latest release, if known.
    public var latest: String

    /// The release page, if known.
    public var url: String

    /// The error detail of a failed check.
    public var message: String

    /// The release tag, if known.
    public var tag: String

    /// The browser download URL of the disk image asset, if any (works only for public repositories).
    public var dmgURL: String

    /// The API URL of the disk image asset, if any (works with a token for private repositories).
    public var assetAPIURL: String

    /// The file name of the disk image asset, if any.
    public var dmgName: String

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - status: The outcome.
    ///   - latest: The display version of the latest release.
    ///   - url: The release page.
    ///   - message: The error detail.
    ///   - tag: The release tag.
    ///   - dmgURL: The browser download URL of the disk image.
    ///   - assetAPIURL: The API URL of the disk image asset.
    ///   - dmgName: The file name of the disk image.
    public init(
        status: UpdateStatus,
        latest: String = "",
        url: String = "",
        message: String = "",
        tag: String = "",
        dmgURL: String = "",
        assetAPIURL: String = "",
        dmgName: String = ""
    ) {
        self.status = status
        self.latest = latest
        self.url = url
        self.message = message
        self.tag = tag
        self.dmgURL = dmgURL
        self.assetAPIURL = assetAPIURL
        self.dmgName = dmgName
    }
}

/// Turns the GitHub release JSON into an update result.
public enum ReleaseEvaluator {
    /// Evaluates the latest release against the installed version.
    ///
    /// - Parameters:
    ///   - release: The release object, or `nil` if it could not be fetched.
    ///   - current: The installed version.
    ///   - repositorySlug: The repository, used for the fallback release page.
    /// - Returns: `unavailable` without a release, otherwise `update` or `current`.
    public static func evaluate(
        _ release: JSONValue?,
        current: String,
        repositorySlug: String = AppInfo.repositorySlug
    ) -> UpdateResult {
        guard let release, let object = release.objectValue, !object.isEmpty else {
            return UpdateResult(status: .unavailable)
        }
        let tag = nonEmpty(release["tag_name"]) ?? nonEmpty(release["name"]) ?? ""
        let url = nonEmpty(release["html_url"]) ?? "https://github.com/\(repositorySlug)/releases"
        let parts = VersionCompare.parse(tag)
        let latest = parts.isEmpty ? tag : parts.map(String.init).joined(separator: ".")
        var result = UpdateResult(
            status: VersionCompare.isNewer(tag, than: current) ? .update : .current,
            latest: latest,
            url: url,
            tag: tag
        )
        for asset in release["assets"]?.arrayValue ?? [] {
            if let name = asset["name"]?.stringValue, AppInfo.isImage(named: name) {
                result.dmgURL = asset["browser_download_url"]?.stringValue ?? ""
                result.assetAPIURL = asset["url"]?.stringValue ?? ""
                result.dmgName = name
                break
            }
        }
        return result
    }

    private static func nonEmpty(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue, !text.isEmpty else {
            return nil
        }
        return text
    }
}

/// The schedule of the silent update check: at launch and then periodically, so a new release is offered within
/// hours of its upload; the notification is posted once per release.
public enum UpdateSchedule {
    /// The seconds between two silent checks while the app runs.
    public static let interval: TimeInterval = 3 * 3600

    /// Returns whether a silent check result deserves a notification.
    ///
    /// - Parameters:
    ///   - result: The result of the silent check.
    ///   - notified: The display version of the last release a notification was posted for.
    /// - Returns: `true` for an update to a release that was not announced yet.
    public static func shouldNotify(_ result: UpdateResult, notified: String) -> Bool {
        result.status == .update && result.latest != notified
    }
}
