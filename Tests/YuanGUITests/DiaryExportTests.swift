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
