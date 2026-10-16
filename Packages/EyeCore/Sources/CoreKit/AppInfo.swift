/// Static identity of the application that must stay stable across releases.
///
/// The bundle identifier is the key for TCC grants (camera, Accessibility), so changing it would lose the granted
/// permissions.
public enum AppInfo {
    /// The bundle identifier of the application.
    public static let bundleIdentifier = "com.deanbean.eyetracking"

    /// The user-facing name of the application, used as notification title.
    public static let displayName = "Eye Tracking"

    /// The GitHub repository slug that the updater queries for releases.
    public static let repositorySlug = "DeanBeanBEER-WARE/eye-tracking"

    /// The GitHub account with access to the private repository, whose `gh` token the updater uses.
    public static let githubAccount = "DeanBeanBEER-WARE"

    /// The directory name used below `Application Support` and `Logs`.
    public static let directoryName = "EyeTracking"

    /// The file name prefix of the release disk images, as in `EyeTracking-0.1.0.dmg`.
    public static let imagePrefix = "EyeTracking-"

    /// Whether a release asset is a disk image of the app.
    ///
    /// - Parameter name: The file name of the asset.
    /// - Returns: `true` for `EyeTracking-<version>.dmg`.
    public static func isImage(named name: String) -> Bool {
        name.hasPrefix(imagePrefix) && name.hasSuffix(".dmg")
    }
}
