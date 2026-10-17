public enum AppLocation: Equatable, Sendable {
    case notBundled

    case needsApplicationsFolder

    public static func problem(bundlePath: String) -> AppLocation? {
        guard bundlePath.hasSuffix(".app") || bundlePath.hasSuffix(".app/") else {
            return .notBundled
        }
        if bundlePath.contains("AppTranslocation") || bundlePath.hasPrefix("/Volumes/") {
            return .needsApplicationsFolder
        }
        return nil
    }
}
