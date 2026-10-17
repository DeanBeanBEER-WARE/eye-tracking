public enum VersionCompare {
    public static func parse(_ text: String) -> [Int] {
        guard let match = text.firstMatch(of: #/\d+(?:\.\d+)*/#.asciiOnlyDigits()) else {
            return []
        }
        return match.output.split(separator: ".").compactMap { Int($0) }
    }

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
