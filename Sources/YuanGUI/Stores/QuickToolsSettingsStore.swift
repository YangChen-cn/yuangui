import Carbon.HIToolbox
import Foundation

@MainActor
final class QuickToolsSettingsStore: ObservableObject {
    @Published private(set) var screenshotHotKey: HotKeyBinding
    @Published private(set) var screenshotTranslationHotKey: HotKeyBinding
    @Published private(set) var translationHotKey: HotKeyBinding
    @Published private(set) var screenshotDirectoryPath: String
    @Published private(set) var nonChineseTarget: QuickToolLanguage
    @Published private(set) var chineseTarget: QuickToolLanguage
    @Published private(set) var translationEngine: TranslationEngine
    @Published var message: String?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let legacyScreenshotDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: [.control, .shift],
        keyLabel: "A"
    )
    private static let legacyTranslationDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: [.control, .shift],
        keyLabel: "T"
    )

    private enum Key {
        static let screenshotHotKey = "quickTools.screenshotHotKey"
        static let screenshotTranslationHotKey = "quickTools.screenshotTranslationHotKey"
        static let translationHotKey = "quickTools.translationHotKey"
        static let screenshotDirectory = "quickTools.screenshotDirectory"
        static let nonChineseTarget = "quickTools.nonChineseTarget"
        static let chineseTarget = "quickTools.chineseTarget"
        static let translationEngine = "quickTools.translationEngine"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedScreenshot = Self.decodeHotKey(defaults.data(forKey: Key.screenshotHotKey))
        let storedTranslation = Self.decodeHotKey(defaults.data(forKey: Key.translationHotKey))
        screenshotHotKey = storedScreenshot == Self.legacyScreenshotDefault
            ? .screenshotDefault
            : storedScreenshot ?? .screenshotDefault
        screenshotTranslationHotKey = Self.decodeHotKey(defaults.data(forKey: Key.screenshotTranslationHotKey))
            ?? .screenshotTranslationDefault
        translationHotKey = storedTranslation == Self.legacyTranslationDefault
            ? .translationDefault
            : storedTranslation ?? .translationDefault
        screenshotDirectoryPath = defaults.string(forKey: Key.screenshotDirectory)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/YuanGUI Screenshots", isDirectory: true).path
        nonChineseTarget = QuickToolLanguage(rawValue: defaults.string(forKey: Key.nonChineseTarget) ?? "") ?? .simplifiedChinese
        chineseTarget = QuickToolLanguage(rawValue: defaults.string(forKey: Key.chineseTarget) ?? "") ?? .english
        translationEngine = TranslationEngine(rawValue: defaults.string(forKey: Key.translationEngine) ?? "") ?? .systemShortcut

        if storedScreenshot != nil, storedScreenshot != screenshotHotKey {
            defaults.set(try? JSONEncoder().encode(screenshotHotKey), forKey: Key.screenshotHotKey)
        }
        if storedTranslation != nil, storedTranslation != translationHotKey {
            defaults.set(try? JSONEncoder().encode(translationHotKey), forKey: Key.translationHotKey)
        }
    }

    func hotKey(for action: QuickToolAction) -> HotKeyBinding {
        switch action {
        case .regionScreenshot: screenshotHotKey
        case .screenshotTranslation: screenshotTranslationHotKey
        case .translateSelection: translationHotKey
        }
    }

    func saveHotKey(_ binding: HotKeyBinding, for action: QuickToolAction) {
        switch action {
        case .regionScreenshot:
            screenshotHotKey = binding
            defaults.set(try? encoder.encode(binding), forKey: Key.screenshotHotKey)
        case .screenshotTranslation:
            screenshotTranslationHotKey = binding
            defaults.set(try? encoder.encode(binding), forKey: Key.screenshotTranslationHotKey)
        case .translateSelection:
            translationHotKey = binding
            defaults.set(try? encoder.encode(binding), forKey: Key.translationHotKey)
        }
    }

    func resetHotKey(for action: QuickToolAction) {
        saveHotKey(action.defaultHotKey, for: action)
    }

    func setScreenshotDirectory(_ url: URL) {
        screenshotDirectoryPath = url.standardizedFileURL.path
        defaults.set(screenshotDirectoryPath, forKey: Key.screenshotDirectory)
    }

    func setNonChineseTarget(_ language: QuickToolLanguage) {
        nonChineseTarget = language
        defaults.set(language.rawValue, forKey: Key.nonChineseTarget)
    }

    func setChineseTarget(_ language: QuickToolLanguage) {
        chineseTarget = language
        defaults.set(language.rawValue, forKey: Key.chineseTarget)
    }

    func setTranslationEngine(_ engine: TranslationEngine) {
        translationEngine = engine
        defaults.set(engine.rawValue, forKey: Key.translationEngine)
    }

    private static func decodeHotKey(_ data: Data?) -> HotKeyBinding? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(HotKeyBinding.self, from: data)
    }
}

extension QuickToolAction {
    var defaultHotKey: HotKeyBinding {
        switch self {
        case .regionScreenshot: .screenshotDefault
        case .screenshotTranslation: .screenshotTranslationDefault
        case .translateSelection: .translationDefault
        }
    }
}
