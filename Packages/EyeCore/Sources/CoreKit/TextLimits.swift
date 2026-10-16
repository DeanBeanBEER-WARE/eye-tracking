/// Helpers that keep tool output short enough for log messages.
public enum TextLimits {
    /// Returns the trimmed start of a text.
    ///
    /// - Parameters:
    ///   - text: The full text, for example the standard error of a tool.
    ///   - count: The maximum number of Unicode scalars.
    /// - Returns: The text without surrounding whitespace, cut after `count` scalars.
    public static func excerpt(_ text: String, _ count: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(max(0, count))))
    }
}
