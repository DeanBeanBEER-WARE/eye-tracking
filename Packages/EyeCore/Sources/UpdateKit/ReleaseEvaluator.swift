import CoreKit
import Foundation

public enum UpdateStatus: String, Equatable, Sendable {
    case update

    case current

    case unavailable

    case error
}

public struct UpdateResult: Equatable, Sendable {
    public var status: UpdateStatus

    public var latest: String

    public var url: String

    public var message: String

    public var tag: String

    public var dmgURL: String

    public var assetAPIURL: String

    public var dmgName: String

    public var needsAuthentication: Bool

    public init(
        status: UpdateStatus,
        latest: String = "",
        url: String = "",
        message: String = "",
        tag: String = "",
        dmgURL: String = "",
        assetAPIURL: String = "",
        dmgName: String = "",
        needsAuthentication: Bool = false
    ) {
        self.status = status
        self.latest = latest
        self.url = url
        self.message = message
        self.tag = tag
        self.dmgURL = dmgURL
        self.assetAPIURL = assetAPIURL
        self.dmgName = dmgName
        self.needsAuthentication = needsAuthentication
    }
}

public enum ReleaseEvaluator {
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

public enum UpdateSchedule {
    public static let interval: TimeInterval = 3 * 3600

    public static func shouldNotify(_ result: UpdateResult, notified: String) -> Bool {
        result.status == .update && result.latest != notified
    }
}
