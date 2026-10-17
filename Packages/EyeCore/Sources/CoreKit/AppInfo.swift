public enum AppInfo {
    public static let bundleIdentifier = "com.deanbean.eyetracking"

    public static let displayName = "Eye Tracking"

    public static let repositorySlug = "DeanBeanBEER-WARE/eye-tracking"

    public static let githubAccount = "DeanBeanBEER-WARE"

    public static let directoryName = "EyeTracking"

    public static let imagePrefix = "EyeTracking-"

    public static func isImage(named name: String) -> Bool {
        name.hasPrefix(imagePrefix) && name.hasSuffix(".dmg")
    }
}
