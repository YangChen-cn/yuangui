import Foundation

enum TranslationTextFormatter {
    /// Apple Translate and Shortcuts can occasionally return a Traditional
    /// Chinese glyph even when the requested locale is `zh-Hans`.
    static func simplifiedChinese(_ text: String, target: QuickToolLanguage) -> String {
        guard target == .simplifiedChinese else { return text }
        return text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }

    static func addingSemanticLineBreaks(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        let bulletPattern = #"[\t ]+([•▪◦‣⁃])[\t ]+"#
        value = replacing(pattern: bulletPattern, in: value, with: "\n• ")

        let middleDotPattern = #"[\t ]+·[\t ]+"#
        if matches(pattern: middleDotPattern, in: value) >= 2 {
            value = replacing(pattern: middleDotPattern, in: value, with: "\n• ")
        }

        let numberedListPattern = #"[\t ]+(?=\d{1,2}[\.、\)]\s+)"#
        value = replacing(pattern: numberedListPattern, in: value, with: "\n")
        value = replacing(pattern: #"\n[\t ]+"#, in: value, with: "\n")
        value = replacing(pattern: #"\n{3,}"#, in: value, with: "\n\n")

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(pattern: String, in value: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value))
    }

    private static func replacing(pattern: String, in value: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }
}
