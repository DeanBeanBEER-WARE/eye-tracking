import CoreKit

/// Decides whether the running app can replace itself with a downloaded release.
public enum UpdateTarget {
    /// Returns the bundle to replace, if a self-update is possible from its location.
    ///
    /// The bundle must be an app bundle outside a translocated copy or a mounted disk image, and both the bundle and
    /// its parent directory must be writable, otherwise the release page opens instead.
    ///
    /// - Parameters:
    ///   - bundlePath: The path of the main bundle.
    ///   - isWritable: Checks whether a path is writable by the current user.
    /// - Returns: The bundle path without a trailing slash, or `nil` if it cannot be replaced.
    public static func installable(bundlePath: String, isWritable: (String) -> Bool) -> String? {
        guard AppLocation.problem(bundlePath: bundlePath) == nil else {
            return nil
        }
        let bundle = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        guard let slash = bundle.lastIndex(of: "/"), slash != bundle.startIndex else {
            return nil
        }
        let parent = String(bundle[..<slash])
        guard isWritable(bundle), isWritable(parent) else {
            return nil
        }
        return bundle
    }
}
