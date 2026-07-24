import XCTest
@testable import YuanGUI

// MARK: - DiaryEntry 模型测试

final class DiaryEntryTests: XCTestCase {

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

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSaveAndLoad() throws {
        let entry = DiaryEntry(title: "测试", body: "内容")
        try repo.save(entry)
        let loaded = try repo.load(id: entry.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "测试")
        XCTAssertEqual(loaded?.body, "内容")
    }

    func testLoadAll() throws {
        try repo.save(DiaryEntry(body: "第一条"))
        try repo.save(DiaryEntry(body: "第二条"))
        let all = try repo.loadAll()
        XCTAssertEqual(all.count, 2)
    }

    func testDelete() throws {
        let entry = DiaryEntry(body: "要删除的")
        try repo.save(entry)
        try repo.delete(id: entry.id)
        let loaded = try repo.load(id: entry.id)
        XCTAssertNil(loaded)
    }

    func testLoadNonexistentReturnsNil() throws {
        let loaded = try repo.load(id: UUID())
        XCTAssertNil(loaded)
    }

    func testFilenameFormat() throws {
        let entry = DiaryEntry(body: "test")
        try repo.save(entry)
        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir.appendingPathComponent("Entries"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        let filename = files[0].lastPathComponent
        // 文件名格式：{uuid}.diaryentry
        XCTAssertTrue(filename.hasSuffix(".diaryentry"))
        let uuidPart = filename.replacingOccurrences(of: ".diaryentry", with: "")
        XCTAssertEqual(uuidPart.count, 36, "UUID 格式不正确: \(uuidPart)")
    }
}

// MARK: - DiaryAttachmentStore 测试

final class DiaryAttachmentStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: DiaryAttachmentStore!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = DiaryAttachmentStore(baseURL: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSaveAndLoadImage() throws {
        // 创建一个最小的有效 JPEG 数据
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            XCTFail("无法创建测试图片")
            return
        }

        let attachment = try store.saveImage(data: jpegData, originalName: "photo.jpg")
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertTrue(attachment.filename.hasSuffix(".jpg"))

        let loaded = try store.load(attachment: attachment)
        XCTAssertEqual(loaded.count, jpegData.count)
    }

    func testThumbnailGenerated() throws {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            XCTFail("无法创建测试图片")
            return
        }

        let attachment = try store.saveImage(data: jpegData, originalName: "big.jpg")
        let thumbData = try store.loadThumbnail(attachment: attachment)
        XCTAssertNotNil(thumbData)
        XCTAssertTrue(thumbData!.count > 0)
    }

    func testCleanupRemovesUnused() throws {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 50, height: 50).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            XCTFail("无法创建测试图片")
            return
        }

        let attachment = try store.saveImage(data: jpegData, originalName: "temp.jpg")
        // 标记为未使用
        try store.cleanup(usedFilenames: Set<String>())
        // 文件应已被删除
        let loaded = try? store.load(attachment: attachment)
        XCTAssertNil(loaded)
    }
}

// MARK: - DiaryFeature Store 测试

@MainActor
final class DiaryFeatureTests: XCTestCase {

    private var tmpDir: URL!
    private var feature: DiaryFeature!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = DiaryRepository(baseURL: tmpDir)
        let attachmentStore = DiaryAttachmentStore(baseURL: tmpDir)
        let searchService = DiarySearchService()
        feature = DiaryFeature(repository: repo, attachmentStore: attachmentStore, searchService: searchService)
    }

    override func tearDown() {
        feature.flush()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testCreateEntry() {
        let entry = feature.createEntry()
        XCTAssertEqual(feature.entries.count, 1)
        XCTAssertEqual(feature.selectedEntryID, entry.id)
        XCTAssertEqual(entry.body, "")
    }

    func testUpdateEntry() {
        let entry = feature.createEntry()
        var updated = entry
        updated.body = "新内容"
        feature.updateEntry(updated)
        XCTAssertEqual(feature.entries.first?.body, "新内容")
        XCTAssertTrue(feature.isDirty)
    }

    func testDeleteEntry() {
        let entry = feature.createEntry()
        feature.deleteEntry(id: entry.id)
        XCTAssertTrue(feature.entries.isEmpty)
        XCTAssertNil(feature.selectedEntryID)
    }

    func testToggleFavorite() {
        let entry = feature.createEntry()
        XCTAssertFalse(feature.entries.first!.isFavorite)
        feature.toggleFavorite(id: entry.id)
        XCTAssertTrue(feature.entries.first!.isFavorite)
        feature.toggleFavorite(id: entry.id)
        XCTAssertFalse(feature.entries.first!.isFavorite)
    }

    func testLoadFromDisk() throws {
        // 先手动写入一个文件
        let repo = DiaryRepository(baseURL: tmpDir)
        let entry = DiaryEntry(title: "持久化测试", body: "内容")
        try repo.save(entry)

        feature.loadFromDisk()
        XCTAssertEqual(feature.entries.count, 1)
        XCTAssertEqual(feature.entries.first?.title, "持久化测试")
    }

    func testFilteredEntriesBySearch() {
        let e1 = feature.createEntry()
        var u1 = e1
        u1.body = "看电影"
        feature.updateEntry(u1)
        let e2 = feature.createEntry()
        var u2 = e2
        u2.body = "去公园"
        feature.updateEntry(u2)
        feature.searchText = "电影"
        XCTAssertEqual(feature.filteredEntries.count, 1)
    }

    func testFilteredEntriesByTag() {
        let e1 = feature.createEntry()
        var u1 = e1
        u1.tags = ["约会"]
        feature.updateEntry(u1)
        let e2 = feature.createEntry()
        var u2 = e2
        u2.tags = ["居家"]
        feature.updateEntry(u2)
        feature.activeTag = "约会"
        XCTAssertEqual(feature.filteredEntries.count, 1)
    }

    func testFilteredEntriesByFavorites() {
        let e1 = feature.createEntry()
        feature.toggleFavorite(id: e1.id)
        _ = feature.createEntry()
        feature.showFavoritesOnly = true
        XCTAssertEqual(feature.filteredEntries.count, 1)
    }

    func testAllTags() {
        let e1 = feature.createEntry()
        var u1 = e1
        u1.tags = ["B", "A"]
        feature.updateEntry(u1)
        let e2 = feature.createEntry()
        var u2 = e2
        u2.tags = ["C", "A"]
        feature.updateEntry(u2)
        XCTAssertEqual(feature.allTags, ["A", "B", "C"])
    }

    func testDeleteSelectedEntrySelectsNext() {
        let e1 = feature.createEntry()
        let e2 = feature.createEntry()
        feature.selectedEntryID = e1.id
        feature.deleteEntry(id: e1.id)
        XCTAssertEqual(feature.selectedEntryID, e2.id)
    }
}
