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

    func testDisplayTitleWithTitle() {
        let entry = DiaryEntry(title: "今天去约会", body: "正文内容")
        XCTAssertEqual(entry.displayTitle, "今天去约会")
    }

    func testDisplayTitleEmptyTitleFallsBackToBody() {
        let entry = DiaryEntry(title: "", body: "一段很长的正文内容用来测试截断逻辑应该返回前五十个字符")
        XCTAssertEqual(entry.displayTitle, "一段很长的正文内容用来测试截断逻辑应该返回前五十个字符")
    }

    func testDisplayTitleLongBodyTruncates() {
        let longBody = String(repeating: "好", count: 100)
        let entry = DiaryEntry(body: longBody)
        XCTAssertTrue(entry.displayTitle.hasSuffix("…"))
        XCTAssertEqual(entry.displayTitle.count, 51) // 50 chars + "…"
    }

    func testWordCount() {
        let entry = DiaryEntry(body: "Hello 世界")
        XCTAssertEqual(entry.wordCount, 8) // "Hello 世界".count == 8
    }

    func testHasContentEmptyBody() {
        let entry = DiaryEntry(body: "  \n  ")
        XCTAssertFalse(entry.hasContent)
    }

    func testHasContentWithTitle() {
        let entry = DiaryEntry(title: "有标题", body: "")
        XCTAssertTrue(entry.hasContent)
    }

    func testHasContentWithBody() {
        let entry = DiaryEntry(body: "有内容")
        XCTAssertTrue(entry.hasContent)
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

    func testAllCasesHaveEmoji() {
        for mood in DiaryMood.allCases {
            XCTAssertFalse(mood.emoji.isEmpty, "\(mood) emoji 为空")
        }
    }

    func testAllCasesHaveTitle() {
        for mood in DiaryMood.allCases {
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

    func testEmptyQueryReturnsAll() {
        let result = service.search(query: "", in: entries)
        XCTAssertEqual(result.count, 5)
    }

    func testSearchByTitle() {
        let result = service.search(query: "约会", in: entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "第一次约会")
    }

    func testSearchByBody() {
        let result = service.search(query: "电影", in: entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "下雨天")
    }

    func testSearchByTag() {
        let result = service.search(query: "生日", in: entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "生日快乐")
    }

    func testFilterByTag() {
        let result = service.filter(entries: entries, tag: "约会")
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByMood() {
        let result = service.filter(entries: entries, mood: .sad)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterByDateRange() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        // 所有条目默认 occurredAt = Date()，应在范围内
        let result = service.filter(entries: entries, from: yesterday, to: tomorrow)
        XCTAssertEqual(result.count, 5)
    }

    func testFavoritesOnly() {
        let result = service.favorites(in: entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "纪念日")
    }

    func testCombinedQuery() {
        var filter = DiaryQueryFilter()
        filter.text = "电影"
        filter.mood = .calm
        let result = service.query(filter, in: entries)
        XCTAssertEqual(result.count, 1)
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

    func testRepositoryPerformanceWithThousandEntriesAndTwoHundredAttachments() async throws {
        let layout = DiaryStorageLayout(rootURL: tmpDir)
        try FileManager.default.createDirectory(at: layout.originalsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: layout.thumbnailsURL, withIntermediateDirectories: true)
        let attachments = try (0..<200).map { index in
            let filename = "\(UUID().uuidString.lowercased()).jpg"
            let attachment = DiaryAttachment(filename: filename, originalFilename: "photo-\(index).jpg", mimeType: "image/jpeg")
            try Data([0]).write(to: layout.originalsURL.appendingPathComponent(filename))
            try Data([0]).write(to: layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename))
            return attachment
        }
        let entries = (0..<1_000).map { index in
            let lowerBound = index < 10 ? index * 20 : 0
            let entryAttachments = index < 10 ? Array(attachments[lowerBound..<(lowerBound + 20)]) : []
            return DiaryEntry(title: "日记 \(index)", body: "内容 \(index)", attachments: entryAttachments)
        }

        let start = ContinuousClock.now
        let saveReport = await repo.save(entries)
        let loadReport = try await repo.loadAll()
        let elapsed = start.duration(to: .now)

        XCTAssertTrue(saveReport.succeeded)
        XCTAssertEqual(loadReport.entries.count, 1_000)
        XCTAssertLessThan(elapsed, .seconds(15))
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
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(feature.filteredEntries.map(\.id), [first.id])
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
