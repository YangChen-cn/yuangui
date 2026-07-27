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

    func testMusicRuntimeKeysExistInBothLanguagesAndFormatInEnglish() {
        let keys = [
            "music.library.trackCount",
            "music.queue.remainingCount",
            "music.source.currentFormat",
            "music.accessibility.nowPlaying",
            "music.import.addedCount",
            "music.bilibili.favorite.emptyFolder",
            "music.bilibili.favorite.importResult",
            "music.bilibili.playbackExpiredDetail",
            "music.bilibili.account.manage",
            "music.bilibili.videoCount",
            "music.bilibili.importProgress",
            "music.bilibili.apiError",
            "music.bilibili.favorite.apiError",
            "music.bilibili.login.apiError",
            "music.playMode.currentFormat",
            "music.lyrics.matchResult",
            "music.lyrics.metadataSaved",
            "music.lyrics.jumpToTime",
            "music.lyrics.lineAccessibility"
        ]
        let english = AppLocalizer.localizedValues(for: "en")
        let chinese = AppLocalizer.localizedValues(for: "zh-Hans")
        for key in keys {
            XCTAssertNotNil(english[key], "Missing English key: \(key)")
            XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
        }
        XCTAssertEqual(
            String(format: tryUnwrap(english["music.library.trackCount"]), 3),
            "3 songs"
        )
        XCTAssertEqual(
            String(
                format: tryUnwrap(english["music.bilibili.favorite.importResult"]),
                "Favorites",
                4,
                1,
                2
            ),
            "From “Favorites”: imported 4 · skipped 1 duplicates · 2 videos failed"
        )
    }

    func testDiaryAndQuickToolsRuntimeKeysExistInBothLanguagesAndFormatInEnglish() {
        let keys = [
            "quickTools.defaultShortcut",
            "quickTools.hotKeySaved",
            "diary.metadata.listening",
            "diary.sidebar.entryCount",
            "diary.sidebar.photoCount",
            "diary.list.selectedCount",
            "diary.list.entryCount",
            "diary.list.batchDeleteConfirmation",
            "diary.recentlyDeleted.permanentDeleteConfirmation",
            "diary.recentlyDeleted.deletedAt",
            "diary.photoWall.photoCount",
            "diary.quickEntry.pendingPhotos",
            "diary.recoveredFiles",
            "quickTools.accessibilitySettingsHelp",
            "quickTools.replacementFailed",
            "diary.detail.characterCount",
            "diary.export.failed",
            "diary.onThisDay.yearsAgo",
            "diary.weekday.sunday",
            "diary.weekday.monday",
            "diary.weekday.tuesday",
            "diary.weekday.wednesday",
            "diary.weekday.thursday",
            "diary.weekday.friday",
            "diary.weekday.saturday"
        ]
        let english = AppLocalizer.localizedValues(for: "en")
        let chinese = AppLocalizer.localizedValues(for: "zh-Hans")
        for key in keys {
            XCTAssertNotNil(english[key], "Missing English key: \(key)")
            XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
        }
        XCTAssertEqual(
            String(format: tryUnwrap(english["quickTools.defaultShortcut"]), "YuanGUI.Translate"),
            "Default Shortcut: YuanGUI.Translate"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["quickTools.hotKeySaved"]), "Translate Selected Text", "⌃Z"),
            "Set Translate Selected Text shortcut: ⌃Z"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["diary.metadata.listening"]), "double take", "Dhruv"),
            "Listening to “double take” by Dhruv"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["diary.list.batchDeleteConfirmation"]), 2),
            "Move 2 journal entries to Recently Deleted?"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["quickTools.replacementFailed"]), "the target is unavailable"),
            "Replacement failed: the target is unavailable"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["diary.detail.characterCount"]), 12),
            "12 characters"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["diary.recoveredFiles"]), 3),
            "3 damaged files were isolated and can be recovered from the Recovery folder."
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
