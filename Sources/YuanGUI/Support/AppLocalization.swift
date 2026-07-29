import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var languageIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    var title: String {
        switch self {
        case .system: AppLocalizer.string("language.system")
        case .english: AppLocalizer.string("language.english")
        case .simplifiedChinese: AppLocalizer.string("language.simplifiedChinese")
        }
    }
}

private enum AppLanguageStorage {
    static let key = "app.language"
}

@MainActor
final class AppLanguageSettings: ObservableObject {
    @Published private(set) var language: AppLanguage
    @Published private(set) var needsRestart = false

    private let defaults: UserDefaults
    nonisolated static let storageKey = AppLanguageStorage.key

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .system
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: Self.storageKey)
        needsRestart = true
    }

    func dismissRestartNotice() { needsRestart = false }
}

enum AppLocalizer {
    private static let languageKey = AppLanguageStorage.key
    private static var allowsModuleFallback: Bool {
        allowsModuleFallback(for: Bundle.main.bundleURL)
    }

    /// Must run before the first window is created. Apple resolves ordinary SwiftUI
    /// `Text` literals from the main bundle using this per-app language preference.
    static func bootstrap(defaults: UserDefaults = .standard) {
        let language = AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .system
        if let identifier = language.languageIdentifier {
            defaults.set([identifier], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    static var effectiveLanguage: AppLanguage {
        let moduleIdentifier = allowsModuleFallback ? Bundle.module.preferredLocalizations.first : nil
        let identifier = Bundle.main.preferredLocalizations.first ?? moduleIdentifier ?? "en"
        return identifier.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
    }

    static func string(_ key: String, comment: String = "") -> String {
        let mainValue = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if mainValue != key { return mainValue }
        guard allowsModuleFallback else { return key }
        let moduleValue = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        return moduleValue == key ? key : moduleValue
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    static func localizedValues(for identifier: String) -> [String: String] {
        let resourceBundle = allowsModuleFallback ? Bundle.module : Bundle.main
        guard let url = resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: identifier),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return dictionary
    }

    static func localizationKeys(for identifier: String) -> Set<String> {
        Set(localizedValues(for: identifier).keys)
    }

    static func allowsModuleFallback(for bundleURL: URL) -> Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") != .orderedSame
    }
}
