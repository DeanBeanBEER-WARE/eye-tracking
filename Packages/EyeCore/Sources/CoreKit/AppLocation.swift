/// The reasons the running app cannot replace itself or register as a login item from its current location.
public enum AppLocation: Equatable, Sendable {
    /// The app does not run from an app bundle, for example from a test runner.
    case notBundled

    /// The app runs from a translocated copy or a mounted disk image.
    case needsApplicationsFolder

    /// Checks the location of the running app.
    ///
    /// - Parameter bundlePath: The path of the main bundle.
    /// - Returns: The problem, or `nil` if the location is a regular installation.
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
