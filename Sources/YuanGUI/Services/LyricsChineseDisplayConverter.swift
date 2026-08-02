import Foundation
import NaturalLanguage

struct LyricsChineseDisplayConverter {
    enum TargetScript: Hashable {
        case simplified
        case traditional
        case unchanged
    }

    private var detectedLanguage: NLLanguage?
    private var cache: [CacheKey: String] = [:]

    mutating func prepare(document: LyricsDocument?) {
        let sample = document.map { LyricsParser.detectionSample(from: $0) } ?? ""
        prepare(detectionSample: sample)
    }

    mutating func prepare(detectionSample: String) {
        cache.removeAll(keepingCapacity: true)
        detectedLanguage = Self.detectLanguage(in: detectionSample)
    }

    mutating func displayedText(
        _ text: String,
        mode: LyricsChineseConversionMode,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let target = Self.targetScript(for: mode, preferredLanguages: preferredLanguages)
        guard shouldConvert(to: target) else { return text }
        let key = CacheKey(text: text, target: target)
        if let converted = cache[key] { return converted }

        let transform: StringTransform
        switch target {
        case .simplified: transform = StringTransform("Traditional-Simplified")
        case .traditional: transform = StringTransform("Simplified-Traditional")
        case .unchanged: return text
        }
        let converted = text.applyingTransform(transform, reverse: false) ?? text
        cache[key] = converted
        return converted
    }

    static func detectLanguage(in sample: String) -> NLLanguage? {
        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage
    }

    static func targetScript(
        for mode: LyricsChineseConversionMode,
        preferredLanguages: [String]
    ) -> TargetScript {
        switch mode {
        case .simplified: return .simplified
        case .traditional: return .traditional
        case .unchanged: return .unchanged
        case .automatic:
            guard let identifier = preferredLanguages.first?.lowercased() else { return .unchanged }
            if identifier.contains("hant")
                || identifier.hasPrefix("zh-tw")
                || identifier.hasPrefix("zh-hk")
                || identifier.hasPrefix("zh-mo") {
                return .traditional
            }
            if identifier.contains("hans")
                || identifier.hasPrefix("zh-cn")
                || identifier.hasPrefix("zh-sg")
                || identifier.hasPrefix("zh-my") {
                return .simplified
            }
            return .unchanged
        }
    }

    private func shouldConvert(to target: TargetScript) -> Bool {
        switch (target, detectedLanguage) {
        case (.simplified, .traditionalChinese), (.traditional, .simplifiedChinese): true
        default: false
        }
    }

    private struct CacheKey: Hashable {
        let text: String
        let target: TargetScript
    }
}
