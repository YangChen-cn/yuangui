import XCTest
@testable import YuanGUI

final class LocalizationTests: XCTestCase {
    func testEnglishAndSimplifiedChineseHaveTheSameKeys() {
        let english = AppLocalizer.localizationKeys(for: "en")
        let chinese = AppLocalizer.localizationKeys(for: "zh-Hans")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(english, chinese)
    }

    func testEnglishResourceValuesContainNoChineseInterfaceText() {
        for (key, value) in AppLocalizer.localizedValues(for: "en") {
            XCTAssertFalse(value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, key)
        }
    }

    @MainActor
    func testLanguageSettingPersistsWithoutChangingUserContent() {
        let suite = "LocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("custom prompt", forKey: "aiSystemPrompt")
        let settings = AppLanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.language, .system)
        settings.setLanguage(.english)
        XCTAssertTrue(settings.needsRestart)
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .english)
        XCTAssertEqual(defaults.string(forKey: "aiSystemPrompt"), "custom prompt")
    }
}
