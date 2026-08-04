import XCTest
@testable import YuanGUI

// MARK: - DiaryEntry 模型测试

final class DiaryEntryTests: XCTestCase {

    @MainActor
    func testDiaryTextViewHandlesImagePasteInsideTheBodyEditor() {
        let textView = DiaryTextView()
        var pasteCount = 0
        textView.onPasteImage = {
            pasteCount += 1
            return true
        }

        textView.paste(nil)

        XCTAssertEqual(pasteCount, 1)
    }

    func testCodableRoundTrip() throws {
        let entry = DiaryEntry(
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "测试标题",
            body: "测试正文",
            mood: .love,
            tags: ["恋爱", "日常"],
            isFavorite: true
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DiaryEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.title, "测试标题")
        XCTAssertEqual(decoded.body, "测试正文")
        XCTAssertEqual(decoded.mood, .love)
        XCTAssertEqual(decoded.tags, ["恋爱", "日常"])
        XCTAssertTrue(decoded.isFavorite)
    }

    func testDefaultValues() {
        let entry = DiaryEntry()
        XCTAssertNil(entry.title)
        XCTAssertEqual(entry.body, "")
        XCTAssertNil(entry.mood)
        XCTAssertTrue(entry.tags.isEmpty)
        XCTAssertNil(entry.weather)
        XCTAssertNil(entry.music)
        XCTAssertNil(entry.locationName)
        XCTAssertTrue(entry.attachments.isEmpty)
        XCTAssertFalse(entry.isFavorite)
    }

    func testDisplayTitleVariants() {
        let longBody = String(repeating: "好", count: 100)
        let cases: [(DiaryEntry, String, Bool)] = [
            (DiaryEntry(title: "今天去约会", body: "正文内容"), "今天去约会", false),
            (
                DiaryEntry(title: "", body: "一段很长的正文内容用来测试截断逻辑应该返回前五十个字符"),
                "一段很长的正文内容用来测试截断逻辑应该返回前五十个字符",
                false
            ),
            (DiaryEntry(body: longBody), "", true)
        ]

        for (entry, expected, shouldTruncate) in cases {
            if shouldTruncate {
                XCTAssertTrue(entry.displayTitle.hasSuffix("…"))
                XCTAssertEqual(entry.displayTitle.count, 51) // 50 chars + "…"
            } else {
                XCTAssertEqual(entry.displayTitle, expected)
            }
        }
    }

    func testWordCount() {
        let entry = DiaryEntry(body: "Hello 世界")
        XCTAssertEqual(entry.wordCount, 8) // "Hello 世界".count == 8
    }

    func testHasContentVariants() {
        let cases: [(DiaryEntry, Bool)] = [
            (DiaryEntry(body: "  \n  "), false),
            (DiaryEntry(title: "有标题", body: ""), true),
            (DiaryEntry(body: "有内容"), true)
        ]

        for (entry, expected) in cases {
            XCTAssertEqual(entry.hasContent, expected)
        }
    }

    func testHashable() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = DiaryEntry(id: id, occurredAt: date, createdAt: date, updatedAt: date, body: "a")
        let b = DiaryEntry(id: id, occurredAt: date, createdAt: date, updatedAt: date, body: "a")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}

// MARK: - DiaryMood 测试

final class DiaryMoodTests: XCTestCase {

    func testMoodSetProvidesBroadEverydayRange() {
        XCTAssertGreaterThanOrEqual(DiaryMood.allCases.count, 16)
        XCTAssertTrue(DiaryMood.allCases.contains(.sweet))
        XCTAssertTrue(DiaryMood.allCases.contains(.tired))
        XCTAssertTrue(DiaryMood.allCases.contains(.wronged))
    }

    func testAllCasesHaveUserFacingMetadata() {
        for mood in DiaryMood.allCases {
            XCTAssertFalse(mood.emoji.isEmpty, "\(mood) emoji 为空")
            XCTAssertFalse(mood.title.isEmpty, "\(mood) title 为空")
        }
    }

    func testCodableRoundTrip() throws {
        for mood in DiaryMood.allCases {
            let data = try JSONEncoder().encode(mood)
            let decoded = try JSONDecoder().decode(DiaryMood.self, from: data)
            XCTAssertEqual(decoded, mood)
        }
    }
}

// MARK: - DiarySearchService 测试

@MainActor
final class DiarySearchServiceTests: XCTestCase {

    private let service = DiarySearchService()
    private var entries: [DiaryEntry] = []

    override func setUp() {
        entries = [
            DiaryEntry(title: "第一次约会", body: "去了公园散步", mood: .love, tags: ["约会", "公园"]),
            DiaryEntry(title: "下雨天", body: "在家看电影", mood: .calm, tags: ["电影", "居家"]),
            DiaryEntry(title: "生日快乐", body: "收到了礼物", mood: .happy, tags: ["生日"]),
            DiaryEntry(title: nil, body: "今天心情不好", mood: .sad, tags: ["心情"]),
            DiaryEntry(title: "纪念日", body: "一周年", isFavorite: true),
        ]
    }

    func testSearchAndFilterMatrix() {
        let searchCases: [(String, UUID?)] = [
            ("", nil),
            ("约会", entries[0].id),
            ("电影", entries[1].id),
            ("生日", entries[2].id)
        ]
        for (query, expectedID) in searchCases {
            let result = service.search(query: query, in: entries)
            if let expectedID {
                XCTAssertEqual(result.map(\.id), [expectedID])
            } else {
                XCTAssertEqual(result.count, entries.count)
            }
        }

        XCTAssertEqual(service.filter(entries: entries, tag: "约会").map(\.id), [entries[0].id])
        XCTAssertEqual(service.filter(entries: entries, mood: .sad).map(\.id), [entries[3].id])

        let now = Date()
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else {
            XCTFail("Unable to construct date range")
            return
        }
        // 所有条目默认 occurredAt = Date()，应在范围内
        let result = service.filter(entries: entries, from: yesterday, to: tomorrow)
        XCTAssertEqual(result.count, entries.count)
        XCTAssertEqual(service.favorites(in: entries).map(\.id), [entries[4].id])

        var filter = DiaryQueryFilter()
        filter.text = "电影"
        filter.mood = .calm
        XCTAssertEqual(service.query(filter, in: entries).map(\.id), [entries[1].id])
    }
}

// MARK: - DiaryAttachment 测试

final class DiaryAttachmentTests: XCTestCase {

    func testThumbnailFilename() {
        let attachment = DiaryAttachment(
            filename: "ABC123.jpg",
            originalFilename: "photo.jpg",
            mimeType: "image/jpeg"
        )
        XCTAssertEqual(attachment.thumbnailFilename, "ABC123.thumb.jpg")
    }

    func testCodableRoundTrip() throws {
        let attachment = DiaryAttachment(
            filename: "test.png",
            originalFilename: "我的照片.png",
            mimeType: "image/png"
        )
        let data = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(DiaryAttachment.self, from: data)
        XCTAssertEqual(decoded.id, attachment.id)
        XCTAssertEqual(decoded.filename, "test.png")
        XCTAssertEqual(decoded.originalFilename, "我的照片.png")
    }
}

// MARK: - DiaryRepository 测试

final class DiaryRepositoryTests: XCTestCase {
    private var tmpDir: URL!
    private var repo: DiaryRepository!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repo = DiaryRepository(baseURL: tmpDir)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: tmpDir) }

    func testSaveUsesVersionedEnvelopeAndLoadsEntry() async throws {
        let entry = DiaryEntry(title: "测试", body: "内容")
        try await repo.save(entry)
        let loaded = try await repo.load(id: entry.id)
        XCTAssertEqual(loaded?.body, "内容")
        let url = tmpDir.appendingPathComponent("Entries/\(entry.id.uuidString.lowercased()).diaryentry")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DiaryFileEnvelope.self, from: Data(contentsOf: url))
        XCTAssertEqual(envelope.formatVersion, DiaryFileEnvelope.currentFormatVersion)
    }

    func testLegacyBareEntryLoads() async throws {
        let entry = DiaryEntry(title: "旧格式", body: "内容")
        let directory = tmpDir.appendingPathComponent("Entries")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: directory.appendingPathComponent("\(entry.id.uuidString).diaryentry"))
        let report = try await repo.loadAll()
        XCTAssertEqual(report.entries.first?.title, "旧格式")
    }

    func testCorruptEntryIsIsolatedWithoutBlockingOthers() async throws {
        let valid = DiaryEntry(title: "正常", body: "内容")
        try await repo.save(valid)
        try Data("broken".utf8).write(to: tmpDir.appendingPathComponent("Entries/broken.diaryentry"))
        let report = try await repo.loadAll()
        XCTAssertEqual(report.entries.map(\.id), [valid.id])
        XCTAssertEqual(report.recoveredFiles.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.recoveredFiles[0].path))
    }

    func testRecentlyDeletedCanRestore() async throws {
        let entry = DiaryEntry(title: "删除", body: "内容")
        try await repo.save(entry)
        _ = try await repo.moveToRecentlyDeleted(entry)
        let deletedEntry = try await repo.load(id: entry.id)
        let deletedItems = try await repo.recentlyDeleted()
        XCTAssertNil(deletedEntry)
        XCTAssertEqual(deletedItems.count, 1)
        let restored = try await repo.restoreDeleted(id: entry.id)
        XCTAssertEqual(restored.id, entry.id)
        let restoredEntry = try await repo.load(id: entry.id)
        XCTAssertNotNil(restoredEntry)
    }

}

// MARK: - DiaryAttachmentStore 测试

final class DiaryAttachmentStoreTests: XCTestCase {
    private var tmpDir: URL!
    private var layout: DiaryStorageLayout!
    private var store: DiaryAttachmentStore!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        layout = DiaryStorageLayout(rootURL: tmpDir)
        store = DiaryAttachmentStore(layout: layout)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: tmpDir) }

    func testSaveLoadAndThumbnailUseSeparateDirectories() async throws {
        let data = try makeJPEG(color: .red, size: NSSize(width: 100, height: 100))
        let attachment = try await store.saveImage(data: data, originalName: "photo.jpg")
        let loaded = try await store.load(attachment: attachment)
        let thumbnail = try await store.loadThumbnail(attachment: attachment)
        XCTAssertEqual(loaded, data)
        XCTAssertNotNil(thumbnail)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.originalsURL.appendingPathComponent(attachment.filename).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename).path))
    }

    func testCleanupDoesNotDeleteThumbnailDirectory() async throws {
        let data = try makeJPEG(color: .green, size: NSSize(width: 50, height: 50))
        let attachment = try await store.saveImage(data: data, originalName: "temp.jpg")
        try await store.cleanup(usedFilenames: [])
        let loaded = try? await store.load(attachment: attachment)
        XCTAssertNil(loaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.thumbnailsURL.path))
    }

    func testRemoveDeletesOriginalAndThumbnail() async throws {
        let data = try makeJPEG(color: .blue, size: NSSize(width: 50, height: 50))
        let attachment = try await store.saveImage(data: data, originalName: "remove.jpg")
        try await store.remove(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.originalsURL.appendingPathComponent(attachment.filename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename).path))
    }

    func testMultipleImageImportKeepsSuccessesAndReportsFailures() async throws {
        let validData = try makeJPEG(color: .purple, size: NSSize(width: 40, height: 40))
        let valid = try await store.prepare(data: validData, originalName: "valid.jpg")
        let invalid = DiaryPreparedImage(data: Data("bad".utf8), originalName: "invalid.jpg", fileExtension: "jpg", mimeType: "image/jpeg")

        let report = await store.save([valid, invalid])

        XCTAssertEqual(report.attachments.count, 1)
        XCTAssertEqual(report.failures.map(\.name), ["invalid.jpg"])
        let savedData = try await store.load(attachment: report.attachments[0])
        XCTAssertEqual(savedData, validData)
    }

    func testRejectsInvalidAndUnsafeImages() async throws {
        do {
            _ = try await store.saveImage(data: Data("bad".utf8), originalName: "bad.jpg")
            XCTFail("Expected invalid image")
        } catch {}
        do {
            _ = try await store.saveImage(
                data: Data(count: DiaryAttachmentStore.maximumFileSize + 1),
                originalName: "large.jpg"
            )
            XCTFail("Expected oversized image rejection")
        } catch {}
        let unsafe = DiaryAttachment(filename: "../evil.jpg", originalFilename: "evil.jpg", mimeType: "image/jpeg")
        do {
            _ = try await store.load(attachment: unsafe)
            XCTFail("Expected unsafe filename rejection")
        } catch {}
    }

    private func makeJPEG(color: NSColor, size: NSSize) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "DiaryTests", code: 1)
        }
        return data
    }
}

// MARK: - DiaryFeature Store 测试

@MainActor
final class DiaryFeatureTests: XCTestCase {
    private var tmpDir: URL!
    private var layout: DiaryStorageLayout!
    private var feature: DiaryFeature!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        layout = DiaryStorageLayout(rootURL: tmpDir, temporaryURL: tmpDir.appendingPathComponent("Temp"))
        feature = DiaryFeature(layout: layout)
    }

    override func tearDown() async throws {
        _ = await feature.flush()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testDirtyIDsFlushAndLoadIfNeededDoesNotOverwriteMemory() async throws {
        let entry = feature.createEntry()
        var draft = DiaryDraft(entry: entry)
        draft.body = "第一次"
        feature.updateDraft(draft)
        XCTAssertEqual(feature.dirtyEntryIDs, [entry.id])
        let didFlush = await feature.flush()
        XCTAssertTrue(didFlush)
        XCTAssertTrue(feature.dirtyEntryIDs.isEmpty)
        await feature.loadIfNeeded()
        draft.body = "未保存编辑"
        feature.updateDraft(draft)
        await feature.loadIfNeeded()
        XCTAssertEqual(feature.entries.first?.body, "未保存编辑")
    }

    func testEditDuringSaveKeepsNewRevisionDirtyUntilItIsPersisted() async throws {
        let gate = FirstDiarySaveGate()
        let repository = DiaryRepository(
            layout: layout,
            beforeBatchSave: { await gate.pauseFirstSave() }
        )
        let delayedFeature = DiaryFeature(
            repository: repository,
            attachmentStore: DiaryAttachmentStore(layout: layout),
            exportService: DiaryExportService(layout: layout),
            searchService: DiarySearchService()
        )
        let entry = delayedFeature.createEntry()
        var draft = DiaryDraft(entry: entry)
        draft.body = "保存开始时的内容"
        delayedFeature.updateDraft(draft)

        let flushTask = Task { @MainActor in await delayedFeature.flush() }
        await gate.waitUntilPaused()
        draft.body = "保存等待期间的新内容"
        delayedFeature.updateDraft(draft)
        await gate.resume()

        let didFlush = await flushTask.value
        XCTAssertTrue(didFlush)
        XCTAssertTrue(delayedFeature.dirtyEntryIDs.isEmpty)
        let persisted = try await repository.load(id: entry.id)
        XCTAssertEqual(persisted?.body, "保存等待期间的新内容")
    }

    func testPartialSaveFailureKeepsOnlyFailedEntryDirty() async throws {
        let failedEntry = feature.createEntry()
        var failedDraft = DiaryDraft(entry: failedEntry)
        failedDraft.body = "保存失败"
        feature.updateDraft(failedDraft)
        let savedEntry = feature.createEntry()
        var savedDraft = DiaryDraft(entry: savedEntry)
        savedDraft.body = "保存成功"
        feature.updateDraft(savedDraft)

        try FileManager.default.createDirectory(at: layout.entriesURL, withIntermediateDirectories: true)
        let blockedURL = layout.entriesURL.appendingPathComponent("\(failedEntry.id.uuidString.lowercased()).diaryentry")
        try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: true)
        let didFlush = await feature.flush()

        XCTAssertFalse(didFlush)
        XCTAssertEqual(feature.dirtyEntryIDs, [failedEntry.id])
        let repository = DiaryRepository(layout: layout)
        let persisted = try await repository.load(id: savedEntry.id)
        XCTAssertEqual(persisted?.body, "保存成功")

        try FileManager.default.removeItem(at: blockedURL)
        let didRetry = await feature.flush()
        XCTAssertTrue(didRetry)
    }

    func testDraftUpdateDoesNotOverwriteFavorite() {
        let entry = feature.createEntry()
        var draft = DiaryDraft(entry: entry)
        feature.toggleFavorite(id: entry.id)
        draft.body = "正文"
        feature.updateDraft(draft)
        XCTAssertTrue(feature.entries.first?.isFavorite == true)
    }

    func testMusicSnapshotRequiresActivePlayback() {
        let track = MusicTrack.appleMusic(
            title: "正在听的歌",
            artist: "歌手",
            album: nil,
            duration: 180
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(DiaryFeature.diaryMusicSnapshot(track: track, isPlaying: false, capturedAt: capturedAt))
        let snapshot = DiaryFeature.diaryMusicSnapshot(track: track, isPlaying: true, capturedAt: capturedAt)
        XCTAssertEqual(snapshot?.title, "正在听的歌")
        XCTAssertEqual(snapshot?.artist, "歌手")
        XCTAssertEqual(snapshot?.capturedAt, capturedAt)
    }

    func testAutoSaveWaitsForEditingCompletionBeforePresentingFeedback() async {
        var feedbackCount = 0
        feature.onEntryCompleted = { feedbackCount += 1 }
        let entry = feature.createEntry()
        var draft = DiaryDraft(entry: entry)
        draft.body = "今天的故事"
        feature.updateDraft(draft)

        let autoSaved = await feature.flush()
        XCTAssertTrue(autoSaved)
        XCTAssertEqual(feedbackCount, 0)
        let firstCompletion = await feature.completeEditingSession(id: entry.id)
        XCTAssertTrue(firstCompletion)
        XCTAssertEqual(feedbackCount, 1)
        let repeatedCompletion = await feature.completeEditingSession(id: entry.id)
        XCTAssertTrue(repeatedCompletion)
        XCTAssertEqual(feedbackCount, 1)
    }

    func testTagsAreNormalizedAndLimited() {
        let entry = feature.createEntry()
        var draft = DiaryDraft(entry: entry)
        draft.tags = [" #Love ", "love", " 旅行 "]
        feature.updateDraft(draft)
        XCTAssertEqual(feature.entries.first?.tags, ["Love", "旅行"])
    }

    func testMonthAndDayNavigationFilterEntries() {
        let calendar = Calendar.current
        let january = calendar.date(from: DateComponents(year: 2025, month: 1, day: 3))!
        let february = calendar.date(from: DateComponents(year: 2025, month: 2, day: 4))!
        var first = feature.createEntry(occurredAt: january)
        first.body = "一月"
        feature.updateEntry(first)
        var second = feature.createEntry(occurredAt: february)
        second.body = "二月"
        feature.updateEntry(second)
        feature.selectMonth(january)
        XCTAssertEqual(feature.filteredEntries.map(\.id), [first.id])
        feature.selectDay(january)
        XCTAssertEqual(feature.selectedEntryID, first.id)
        XCTAssertEqual(feature.viewMode, .timeline)
    }

    func testEmptyCalendarDateCreatesEntry() {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        feature.selectDay(date)
        XCTAssertEqual(feature.entries.count, 1)
        XCTAssertTrue(Calendar.current.isDate(feature.entries[0].occurredAt, inSameDayAs: date))
    }

    func testCreateAndOpenEntryLeavesEmptySpecialViewAndShowsNewEntry() {
        feature.viewMode = .onThisDay
        feature.filter = DiaryFilter(favoritesOnly: true)
        feature.searchText = "不存在的日记"

        let entry = feature.createAndOpenEntry()

        XCTAssertEqual(feature.viewMode, .timeline)
        XCTAssertEqual(feature.filter, DiaryFilter())
        XCTAssertEqual(feature.searchText, "")
        XCTAssertEqual(feature.selectedEntryID, entry.id)
        XCTAssertEqual(feature.selectedEntry?.id, entry.id)
    }

    func testOnThisDayIncludesAllPriorYears() {
        let calendar = Calendar.current
        let today = Date()
        for years in [1, 2, 3] {
            var entry = feature.createEntry(occurredAt: calendar.date(byAdding: .year, value: -years, to: today)!)
            entry.body = "\(years)"
            feature.updateEntry(entry)
        }
        XCTAssertEqual(feature.onThisDayEntries.count, 3)
    }

    func testDeleteAndRestoreUpdatesMemory() async {
        var entry = feature.createEntry()
        entry.body = "内容"
        feature.updateEntry(entry)
        _ = await feature.deleteEntry(id: entry.id)
        XCTAssertTrue(feature.entries.isEmpty)
        XCTAssertEqual(feature.recentlyDeletedItems.count, 1)
        await feature.restoreDeleted(id: entry.id)
        XCTAssertEqual(feature.entries.first?.id, entry.id)
    }

    func testBatchDeleteRestoreAndPermanentDelete() async {
        var first = feature.createEntry()
        first.body = "第一篇"
        feature.updateEntry(first)
        var second = feature.createEntry()
        second.body = "第二篇"
        feature.updateEntry(second)
        var third = feature.createEntry()
        third.body = "第三篇"
        feature.updateEntry(third)

        let batchIDs = Set([first.id, second.id])
        let deleted = await feature.deleteEntries(ids: batchIDs)
        XCTAssertEqual(Set(deleted.map(\.id)), batchIDs)
        XCTAssertEqual(feature.entries.map(\.id), [third.id])
        XCTAssertEqual(Set(feature.recentlyDeletedItems.map(\.id)), batchIDs)

        let restored = await feature.restoreDeleted(ids: batchIDs)
        XCTAssertEqual(restored, batchIDs)
        XCTAssertEqual(Set(feature.entries.map(\.id)), Set([first.id, second.id, third.id]))

        _ = await feature.deleteEntries(ids: Set([third.id]))
        let permanentlyDeleted = await feature.permanentlyDelete(ids: Set([third.id]))
        XCTAssertEqual(permanentlyDeleted, Set([third.id]))
        XCTAssertFalse(feature.recentlyDeletedItems.contains { $0.id == third.id })
    }

    func testUndoManagerRestoresDeletedEntry() async throws {
        var entry = feature.createEntry()
        entry.body = "可撤销"
        feature.updateEntry(entry)
        let deletedResult = await feature.deleteEntry(id: entry.id)
        let deleted = try XCTUnwrap(deletedResult)
        let undoManager = UndoManager()
        undoManager.registerUndo(withTarget: feature) { target in
            Task { await target.restoreDeleted(id: deleted.id) }
        }

        undoManager.undo()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(feature.entries.first?.id, entry.id)
        XCTAssertTrue(feature.recentlyDeletedItems.isEmpty)
    }

    func testPhotoWallNavigationSelectsOwningEntry() {
        let entry = feature.createEntry()
        feature.filter = DiaryFilter(favoritesOnly: true)
        feature.viewMode = .photoWall

        feature.navigate(to: entry.id)

        XCTAssertEqual(feature.selectedEntryID, entry.id)
        XCTAssertEqual(feature.viewMode, .timeline)
        XCTAssertEqual(feature.filter, DiaryFilter())
    }

    func testDebouncedSearch() async throws {
        var first = feature.createEntry()
        first.body = "看电影"
        feature.updateEntry(first)
        var second = feature.createEntry()
        second.body = "去公园"
        feature.updateEntry(second)
        feature.searchText = "电影"
        let expectedIDs = [first.id]
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while feature.filteredEntries.map(\.id) != expectedIDs,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(feature.filteredEntries.map(\.id), expectedIDs)
    }
}

private actor FirstDiarySaveGate {
    private var didPause = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func pauseFirstSave() async {
        guard !didPause else { return }
        didPause = true
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { resumeContinuation = $0 }
    }

    func waitUntilPaused() async {
        if didPause { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
import XCTest
@testable import YuanGUI

final class DiaryExportTests: XCTestCase {
    private var root: URL!
    private var output: URL!
    private var layout: DiaryStorageLayout!
    private var repository: DiaryRepository!
    private var service: DiaryExportService!

    override func setUp() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("Diary")
        output = base.appendingPathComponent("Output")
        layout = DiaryStorageLayout(rootURL: root, backupURL: base.appendingPathComponent("Backups"), temporaryURL: base.appendingPathComponent("Temp"))
        repository = DiaryRepository(layout: layout)
        service = DiaryExportService(layout: layout)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func testExportMarkdownIncludesMetadataAndRelativeAttachments() async throws {
        try FileManager.default.createDirectory(at: layout.originalsURL, withIntermediateDirectories: true)
        let attachment = DiaryAttachment(filename: "00000000-0000-0000-0000-000000000001.jpg", originalFilename: "photo.jpg", mimeType: "image/jpeg")
        try Data("photo".utf8).write(to: layout.originalsURL.appendingPathComponent(attachment.filename))
        let entry = DiaryEntry(
            title: "第一次约会",
            body: "去了公园",
            mood: .love,
            tags: ["约会"],
            weather: DiaryWeatherSnapshot(temperature: 21, condition: "晴", icon: "sun.max", capturedAt: Date()),
            music: DiaryMusicSnapshot(title: "歌", artist: "歌手", capturedAt: Date()),
            locationName: "公园",
            attachments: [attachment]
        )
        let destination = output.appendingPathComponent("diary.md")
        _ = try await service.exportMarkdown(entries: [entry], to: destination)
        let content = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(content.contains("第一次约会"))
        XCTAssertTrue(content.contains("**地点：** 公园"))
        XCTAssertTrue(content.contains("**天气：**"))
        XCTAssertTrue(content.contains("diary-attachments/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("diary-attachments").path))
    }

    func testExportJSONUsesVersionedDocument() async throws {
        let destination = output.appendingPathComponent("diary.json")
        _ = try await service.exportJSON(entries: [DiaryEntry(title: "测试", body: "内容")], to: destination)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(DiaryExportDocument.self, from: Data(contentsOf: destination))
        XCTAssertEqual(document.formatVersion, 1)
        XCTAssertEqual(document.entries.first?.title, "测试")
    }

    func testBackupPreservesStructureAndExcludesExports() async throws {
        try await repository.save(DiaryEntry(title: "备份测试", body: "内容"))
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        try Data().write(to: exports.appendingPathComponent("old.zip"))
        let destination = output.appendingPathComponent("backup.zip")
        _ = try await service.backup(to: destination)
        let listing = try archiveListing(destination)
        XCTAssertTrue(listing.contains("manifest.json"))
        XCTAssertTrue(listing.contains(where: { $0.hasPrefix("Entries/") }))
        XCTAssertFalse(listing.contains(where: { $0.contains("Exports") || $0.contains("old.zip") }))
    }

    func testAutomaticBackupRunsOncePerDayAndPrunesDailyAndWeeklyArchives() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let manager = DiaryAutoBackupService(
            layout: layout,
            exportService: service,
            calendar: calendar
        )
        let start = Date(timeIntervalSince1970: 1_735_689_600)

        let first = try await manager.backupIfNeeded(now: start)
        let repeated = try await manager.backupIfNeeded(now: start.addingTimeInterval(3_600))
        XCTAssertEqual(first.dailyCount, 1)
        XCTAssertEqual(repeated.dailyCount, 1)

        for offset in 1...12 {
            let date = calendar.date(byAdding: .day, value: offset * 4, to: start)!
            _ = try await manager.backupIfNeeded(now: date)
        }
        let status = try await manager.status()
        XCTAssertEqual(status.dailyCount, DiaryAutoBackupService.dailyRetentionCount)
        XCTAssertEqual(status.weeklyCount, DiaryAutoBackupService.weeklyRetentionCount)
        XCTAssertEqual(status.manualCount, 0)
        XCTAssertNotNil(status.lastAutomaticBackup)
    }

    func testImmediateBackupAlwaysCreatesANewManualArchive() async throws {
        let manager = DiaryAutoBackupService(layout: layout, exportService: service)
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let first = try await manager.backupNow(now: now)
        let second = try await manager.backupNow(now: now)

        XCTAssertNotEqual(first.0, second.0)
        XCTAssertEqual(second.1.manualCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.0.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.0.path))
    }

    func testInvalidBackupDoesNotDeleteExistingDiary() async throws {
        let existing = DiaryEntry(title: "保留", body: "不能丢")
        try await repository.save(existing)
        let invalid = output.appendingPathComponent("invalid.zip")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("not zip".utf8).write(to: invalid)
        do {
            _ = try await service.restore(from: invalid)
            XCTFail("Expected restore failure")
        } catch {}
        let loaded = try await repository.load(id: existing.id)
        XCTAssertEqual(loaded?.body, "不能丢")
    }

    func testBackupRoundTripRestoresEntries() async throws {
        let entry = DiaryEntry(title: "原始", body: "内容")
        try await repository.save(entry)
        let backup = output.appendingPathComponent("backup.zip")
        _ = try await service.backup(to: backup)
        let replacement = DiaryEntry(title: "替换", body: "新内容")
        try await repository.save(replacement)
        let report = try await service.restore(from: backup)
        XCTAssertEqual(report.entries.map(\.id), [entry.id])
        let replacedEntry = try await repository.load(id: replacement.id)
        let restoredEntry = try await repository.load(id: entry.id)
        XCTAssertNil(replacedEntry)
        XCTAssertEqual(restoredEntry?.title, "原始")
    }

    func testRestoreInstallationFailureRollsBackCurrentDiary() async throws {
        var original = DiaryEntry(title: "原始", body: "备份内容")
        try await repository.save(original)
        let backup = output.appendingPathComponent("rollback.zip")
        _ = try await service.backup(to: backup)

        original.body = "当前内容"
        let currentOnly = DiaryEntry(title: "当前新增", body: "不能丢")
        try await repository.save(original)
        try await repository.save(currentOnly)
        let failingService = DiaryExportService(
            layout: layout,
            restoreInstallationValidator: { _ in throw DiaryExportError.restoreFailed("forced") }
        )

        do {
            _ = try await failingService.restore(from: backup)
            XCTFail("Expected restore rollback")
        } catch {}

        let restoredCurrent = try await repository.load(id: original.id)
        let restoredNewEntry = try await repository.load(id: currentOnly.id)
        XCTAssertEqual(restoredCurrent?.body, "当前内容")
        XCTAssertEqual(restoredNewEntry?.body, "不能丢")
    }

    func testRestoreRejectsSymbolicLinkBeforeReplacingDiary() async throws {
        let existing = DiaryEntry(title: "保留", body: "不能丢")
        try await repository.save(existing)
        let source = output.appendingPathComponent("Unsafe", isDirectory: true)
        let originals = source.appendingPathComponent("Attachments/Originals", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: originals.appendingPathComponent("00000000-0000-0000-0000-000000000001.jpg"),
            withDestinationURL: FileManager.default.temporaryDirectory
        )
        let archive = output.appendingPathComponent("unsafe.zip")
        try createArchive(from: source, at: archive, preservingSymbolicLinks: true)

        do {
            _ = try await service.restore(from: archive)
            XCTFail("Expected symbolic link rejection")
        } catch {}

        let loaded = try await repository.load(id: existing.id)
        XCTAssertEqual(loaded?.body, "不能丢")
    }

    private func archiveListing(_ url: URL) throws -> [String] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    private func createArchive(from source: URL, at destination: URL, preservingSymbolicLinks: Bool) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q"] + (preservingSymbolicLinks ? ["-y"] : []) + ["-r", destination.path, "Attachments"]
        process.currentDirectoryURL = source
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

