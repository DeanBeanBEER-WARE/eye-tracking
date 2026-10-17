public enum TextLimits {
    public static func excerpt(_ text: String, _ count: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(max(0, count))))
    }
}
