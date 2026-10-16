/// Parsing and comparison of release version strings such as `v0.1.7`.
public enum VersionCompare {
    /// Extracts the numeric components of the first version number in a text.
    ///
    /// - Parameter text: A tag or version string, for example `v0.1.7`.
    /// - Returns: The components, for example `[0, 1, 7]`, or an empty array if the text holds no number.
    public static func parse(_ text: String) -> [Int] {
        guard let match = text.firstMatch(of: #/\d+(?:\.\d+)*/#.asciiOnlyDigits()) else {
            return []
        }
        return match.output.split(separator: ".").compactMap { Int($0) }
    }

    /// Returns whether a release version is newer than the installed one.
    ///
    /// Missing trailing components count as zero, so `0.1.7` equals `0.1.7.0`.
    ///
    /// - Parameters:
    ///   - latest: The version of the latest release.
    ///   - current: The installed version.
    /// - Returns: `true` if `latest` holds a version number that is greater than `current`.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        let latestParts = parse(latest)
        guard !latestParts.isEmpty else {
            return false
        }
        let currentParts = parse(current)
        let width = max(latestParts.count, currentParts.count)
        let lhs = latestParts + Array(repeating: 0, count: width - latestParts.count)
        let rhs = currentParts + Array(repeating: 0, count: width - currentParts.count)
        return rhs.lexicographicallyPrecedes(lhs)
    }
}
