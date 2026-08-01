import XCTest
@testable import YuanGUI

final class LocalizationTests: XCTestCase {
    func testPackagedApplicationDoesNotUseSwiftPMResourceFallback() {
        XCTAssertFalse(AppLocalizer.allowsModuleFallback(for: URL(fileURLWithPath: "/Applications/YuanGUI.app")))
        XCTAssertFalse(AppLocalizer.allowsModuleFallback(for: URL(fileURLWithPath: "/private/tmp/YuanGUI.app")))
        XCTAssertTrue(AppLocalizer.allowsModuleFallback(for: URL(fileURLWithPath: "/tmp/YuanGUIPackageTests.xctest")))
        XCTAssertTrue(AppLocalizer.allowsModuleFallback(for: URL(fileURLWithPath: "/tmp/YuanGUI")))
    }

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
            "music.lyrics.lineAccessibility",
            "music.library.search.placeholder",
            "music.library.sort.libraryOrder",
            "music.library.sort.direction.current",
            "music.local.revealInFinder",
            "music.local.import.failures.title",
            "music.local.import.failures.count",
            "music.artwork.menu",
            "music.artwork.choose",
            "music.artwork.remove",
            "music.artwork.error.invalidImage",
            "music.artwork.error.fileTooLarge",
            "pet.chatter.period.morning.yuanGui.1",
            "pet.chatter.period.afternoon.vcc.1",
            "pet.chatter.period.evening.duo.1",
            "pet.chatter.period.lateNight.yuanGui.1"
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

        for period in PetChatterPeriod.allCases {
            for modeKey in ["yuanGui", "vcc", "duo"] {
                for index in 1...2 {
                    let key = "pet.chatter.period.\(period.rawValue).\(modeKey).\(index)"
                    XCTAssertNotNil(english[key], "Missing English key: \(key)")
                    XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
                }
            }
        }
    }

    func testDiaryAndQuickToolsRuntimeKeysExistInBothLanguagesAndFormatInEnglish() {
        let keys = [
            "quickTools.defaultShortcut",
            "quickTools.hotKeySaved",
            "chat.error.invalidResponse",
            "YuanGUI 音乐播放器",
            "截图翻译使用 Vision 在本机 OCR。翻译默认通过系统快捷指令免费调用 Apple 翻译；在线 AI 仅在你明确选择时使用。网页与截图等只读来源支持编辑、翻译和复制，但不能替换原文。",
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
            "朗读原文",
            "停止朗读原文",
            "朗读译文",
            "停止朗读译文",
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
        XCTAssertEqual(english["YuanGUI 音乐播放器"], "YuanGUI Music")
        XCTAssertEqual(
            english["截图翻译使用 Vision 在本机 OCR。翻译默认通过系统快捷指令免费调用 Apple 翻译；在线 AI 仅在你明确选择时使用。网页与截图等只读来源支持编辑、翻译和复制，但不能替换原文。"],
            "Screenshot translation uses Vision for on-device OCR. By default, translation calls Apple Translate for free through a system Shortcut; online AI is used only when you explicitly select it. Read-only sources such as webpages and screenshots can be edited, translated, and copied, but their original text cannot be replaced."
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
