import XCTest
@testable import YuanGUI

@MainActor
final class DiaryExportTests: XCTestCase {

    private var tmpDir: URL!
    private var exportService: DiaryExportService!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = DiaryRepository(baseURL: tmpDir)
        let attachmentStore = DiaryAttachmentStore(baseURL: tmpDir)
        exportService = DiaryExportService(repository: repo, attachmentStore: attachmentStore)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testExportMarkdown() throws {
        let entries = [
            DiaryEntry(title: "第一次约会", body: "去了公园", mood: .love, tags: ["约会"]),
            DiaryEntry(title: nil, body: "今天很开心", mood: .happy),
        ]
        let url = try exportService.exportMarkdown(entries: entries)
        XCTAssertTrue(url.pathExtension == "md")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("元圭恋爱手账"))
        XCTAssertTrue(content.contains("第一次约会"))
        XCTAssertTrue(content.contains("去了公园"))
        XCTAssertTrue(content.contains("今天很开心"))
    }

    func testExportJSON() throws {
        let entries = [DiaryEntry(title: "测试", body: "内容")]
        let url = try exportService.exportJSON(entries: entries)
        XCTAssertTrue(url.pathExtension == "json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([DiaryEntry].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.title, "测试")
    }

    func testExportZIP() throws {
        let entries = [DiaryEntry(title: "测试", body: "内容")]
        let url = try exportService.exportZIP(entries: entries)
        XCTAssertTrue(url.pathExtension == "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testBackup() throws {
        let repo = DiaryRepository(baseURL: tmpDir)
        try repo.save(DiaryEntry(title: "备份测试", body: "内容"))
        let url = try exportService.backup()
        XCTAssertTrue(url.pathExtension == "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportEmptyEntries() throws {
        let url = try exportService.exportMarkdown(entries: [])
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("共 0 条日记"))
    }
}
