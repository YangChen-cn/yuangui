import AVFoundation

enum SystemSpeechVoiceResolver {
    static func preferredLanguageIdentifier(for language: QuickToolLanguage) -> String {
        switch language {
        case .simplifiedChinese: "zh-CN"
        case .english: "en-US"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .spanish: "es-ES"
        }
    }

    static func bestAvailableLanguageIdentifier(
        for requestedIdentifier: String?,
        availableIdentifiers: [String]
    ) -> String? {
        guard let preferred = normalizedLanguageIdentifier(requestedIdentifier) else { return nil }
        if let exact = availableIdentifiers.first(where: {
            $0.caseInsensitiveCompare(preferred) == .orderedSame
        }) {
            return exact
        }

        let family = languageFamily(preferred)
        return availableIdentifiers.first(where: { languageFamily($0) == family })
    }

    static func voice(
        for requestedIdentifier: String?,
        availableVoices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> AVSpeechSynthesisVoice? {
        guard let identifier = bestAvailableLanguageIdentifier(
            for: requestedIdentifier,
            availableIdentifiers: availableVoices.map(\.language)
        ) else {
            return nil
        }
        return availableVoices.first {
            $0.language.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    static func normalizedLanguageIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.caseInsensitiveCompare("und") != .orderedSame else {
            return nil
        }

        let lowercased = normalized.lowercased()
        if lowercased == "zh" || lowercased.hasPrefix("zh-hans") || lowercased.hasPrefix("zh-cn") {
            return "zh-CN"
        }
        if lowercased.hasPrefix("zh-hant") || lowercased.hasPrefix("zh-tw") || lowercased.hasPrefix("zh-hk") {
            return "zh-TW"
        }
        if lowercased == "en" { return "en-US" }
        if lowercased == "ja" { return "ja-JP" }
        if lowercased == "ko" { return "ko-KR" }
        if lowercased == "fr" { return "fr-FR" }
        if lowercased == "de" { return "de-DE" }
        if lowercased == "es" { return "es-ES" }
        return normalized
    }

    private static func languageFamily(_ identifier: String) -> String {
        identifier.split(separator: "-", maxSplits: 1).first.map(String.init)?.lowercased()
            ?? identifier.lowercased()
    }
}
