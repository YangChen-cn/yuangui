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

    func testMaintenanceRuntimeKeysExistInBothLanguages() {
        let keys = [
            "maintenance.status.scanningCleanup",
            "maintenance.progress.scanningCategory",
            "maintenance.reason.rebuildableCache",
            "maintenance.result.deletedAndTrashed",
            "maintenance.error.changedAfterScan",
            "maintenance.error.protectedPath",
            "diary.error.saveBeforeQuit"
        ]
        let english = AppLocalizer.localizedValues(for: "en")
        let chinese = AppLocalizer.localizedValues(for: "zh-Hans")
        for key in keys {
            XCTAssertNotNil(english[key], "Missing English key: \(key)")
            XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
        }
        XCTAssertEqual(
            String(format: tryUnwrap(english["maintenance.result.deletedAndTrashed"]), "1 GB", "2 GB"),
            "Permanently removed 1 GB; moved 2 GB to the Trash."
        )
    }

    private func tryUnwrap(_ value: String?) -> String {
        guard let value else {
            XCTFail("Required localization value is missing")
            return ""
        }
        return value
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
