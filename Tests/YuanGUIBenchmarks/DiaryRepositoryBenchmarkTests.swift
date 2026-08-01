import Foundation
import XCTest
@testable import YuanGUI

final class DiaryRepositoryBenchmarkTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testRepositoryPerformanceWithThousandEntriesAndTwoHundredAttachments() async throws {
        let layout = DiaryStorageLayout(rootURL: tmpDir)
        try FileManager.default.createDirectory(at: layout.originalsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: layout.thumbnailsURL, withIntermediateDirectories: true)
        let attachments = try (0..<200).map { index in
            let filename = "\(UUID().uuidString.lowercased()).jpg"
            let attachment = DiaryAttachment(
                filename: filename,
                originalFilename: "photo-\(index).jpg",
                mimeType: "image/jpeg"
            )
            try Data([0]).write(to: layout.originalsURL.appendingPathComponent(filename))
            try Data([0]).write(to: layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename))
            return attachment
        }
        let entries = (0..<1_000).map { index in
            let lowerBound = index < 10 ? index * 20 : 0
            let entryAttachments = index < 10 ? Array(attachments[lowerBound..<(lowerBound + 20)]) : []
            return DiaryEntry(title: "日记 \(index)", body: "内容 \(index)", attachments: entryAttachments)
        }

        let repository = DiaryRepository(baseURL: tmpDir)
        let start = ContinuousClock.now
        let saveReport = await repository.save(entries)
        let loadReport = try await repository.loadAll()
        let elapsed = start.duration(to: .now)

        XCTAssertTrue(saveReport.succeeded)
        XCTAssertEqual(loadReport.entries.count, 1_000)
        XCTAssertLessThan(elapsed, .seconds(18))
    }
}
