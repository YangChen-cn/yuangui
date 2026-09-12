import XCTest
import AppKit
import PDFKit
@testable import YuanGUI

final class PDFConversionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func result(body: String = "中文 **paper**", images: [PDFConversionResult.Manifest.Image] = []) throws -> PDFConversionResult {
        let work = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: work.appendingPathComponent("body.md"))
        return PDFConversionResult(directory: work,
            manifest: .init(images: images, failedPages: [], emptyText: body.isEmpty), preview: body, truncated: false)
    }

    func testExportIncludesImagesAndNeverOverwritesEitherExistingName() throws {
        let converted = try result(images: [.init(name: "page-1.png", page: 1)])
        try Data([1, 2, 3]).write(to: converted.directory.appendingPathComponent("page-1.png"))
        let existing = root.appendingPathComponent("论文 paper.md")
        try Data("keep".utf8).write(to: existing)
        let first = try PDFConversionService.export(converted, to: root, name: "论文 paper")
        XCTAssertEqual(first.lastPathComponent, "论文 paper (1).md")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep")
        let markdown = try String(contentsOf: first, encoding: .utf8)
        XCTAssertTrue(markdown.hasPrefix("中文 **paper**"))
        XCTAssertTrue(markdown.contains("![Page 1]"))
        let image = root.appendingPathComponent("论文 paper (1)_assets/page-1.png")
        XCTAssertEqual(try Data(contentsOf: image), Data([1, 2, 3]))
        XCTAssertTrue(markdown.contains("%E8%AE%BA%E6%96%87%20paper%20(1)_assets/page-1.png"))
        let second = try PDFConversionService.export(converted, to: root, name: "论文 paper")
        XCTAssertEqual(second.lastPathComponent, "论文 paper (2).md")
    }

    func testExportFailureCleansStagingAndPreservesOtherFiles() throws {
        let converted = try result(images: [.init(name: "missing.png", page: 1)])
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertThrowsError(try PDFConversionService.export(converted, to: root, name: "paper"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), before)
        let invalidDestination = root.appendingPathComponent("file")
        try Data().write(to: invalidDestination)
        XCTAssertThrowsError(try PDFConversionService.export(converted, to: invalidDestination, name: "paper"))
    }

    func testPreviewIsBoundedButExportRemainsComplete() throws {
        let body = String(repeating: "中😀a", count: 100_000)
        let converted = try result(body: body)
        let (preview, truncated) = try PDFConversionService.readPreview(converted.bodyURL)
        XCTAssertTrue(truncated)
        XCTAssertEqual(preview.count, 200_000)
        XCTAssertEqual(preview, String(body.prefix(200_000)))
        let exported = try PDFConversionService.export(converted, to: root, name: "large")
        XCTAssertEqual(try String(contentsOf: exported, encoding: .utf8), body)
    }

    func testProcessCancellationTerminatesChildGroup() async throws {
        let marker = root.appendingPathComponent("child")
        let runner = PDFProcessRunner()
        let task = Task {
            try await runner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 30 & echo $! > \"$1\"; wait", "test", marker.path])
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let child = try XCTUnwrap(Int32(String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must throw") }
        catch { XCTAssertTrue(error is CancellationError) }
        for _ in 0..<100 {
            if kill(child, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testConcurrentInstallerCannotRemoveActiveEnvironment() async throws {
        let environment = PDFConversionEnvironment(root: root)
        try FileManager.default.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        let sentinel = environment.directory.appendingPathComponent("in-progress")
        try Data("keep".utf8).write(to: sentinel)
        let descriptor = Darwin.open(root.appendingPathComponent(".install-lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        do { try await environment.install { _ in XCTFail("Must not start installation") }; XCTFail("Lock must reject another installer") }
        catch { XCTAssertEqual(error.localizedDescription, AppLocalizer.string("pdf.error.busy")) }
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testDiaryCachePreservesBlocksAndOnlyReparsesChangedBody() {
        var cache = DiaryMarkdownCache()
        let input = "# Title\n## Sub\n### Small\n**bold** and *italic*\n- item\n---\n```\ncode\n```"
        cache.update(input)
        cache.update(input)
        XCTAssertEqual(cache.parseCount, 1)
        XCTAssertEqual(cache.blocks.count, 7)
        if case .paragraph(let text) = cache.blocks[3] { XCTAssertEqual(String(text.characters), "bold and italic") }
        else { XCTFail("Expected paragraph") }
        cache.update("```\nunclosed")
        XCTAssertEqual(cache.parseCount, 2)
        if case .code(let text) = cache.blocks.first { XCTAssertEqual(text, "unclosed") }
        else { XCTFail("Expected unclosed code block") }
        cache.update("")
        XCTAssertTrue(cache.blocks.isEmpty)
    }

    @MainActor
    func testStoreDiscardsUncontrollableResultAfterCancelAndClose() async throws {
        for close in [false, true] {
            let environment = PDFConversionEnvironment(root: root.appendingPathComponent(UUID().uuidString))
            try FileManager.default.createDirectory(at: environment.python.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: environment.python, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
            try Data().write(to: environment.directory.appendingPathComponent("ready"))
            let converted = try result()
            let store = PDFConversionStore(environment: environment, convert: { _, _ in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
                }
                return converted
            })
            store.select([root.appendingPathComponent("paper.pdf")])
            store.convert()
            await Task.yield()
            if close { store.close() } else { store.cancel() }
            for _ in 0..<100 {
                if !store.isBusy { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertFalse(store.isBusy)
            XCTAssertNil(store.result)
            XCTAssertFalse(FileManager.default.fileExists(atPath: converted.directory.path))
        }
    }

    @MainActor
    func testInstallFailureCanRetryAndInvalidSelectionDoesNotReplaceSource() async throws {
        let store = PDFConversionStore(environment: .init(root: root), install: { _ in
            throw PDFConversionError.message("pdf.error.download")
        })
        let file = root.appendingPathComponent("paper.pdf")
        store.select([file])
        store.select([file, file])
        XCTAssertEqual(store.source, file)
        for _ in 0..<2 {
            store.install()
            for _ in 0..<100 {
                if !store.isBusy { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNotNil(store.error)
            XCTAssertFalse(store.isReady)
            XCTAssertFalse(store.isBusy)
        }
    }

    /// Explicit opt-in: network downloads never run in ordinary product tests.
    func testRealInstallationAndPDFConversion() async throws {
        guard ProcessInfo.processInfo.environment["YUANGUI_TEST_PDF_INSTALL"] == "1" else {
            throw XCTSkip("Opt-in runtime download and real PDF conversion")
        }
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent("runtime"))
        let cancelledInstall = Task {
            try await environment.install { stage in
                if stage == "python" { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { try await cancelledInstall.value; XCTFail("Installation cancellation must throw") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(environment.isReady)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.directory.path))
        try await environment.install { print("PDF install: \($0)") }
        XCTAssertTrue(environment.isReady)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent("bin").path))
        // A second install is a read-only fast path.
        try await environment.install { _ in XCTFail("Ready environment should not reinstall") }
        let pdf = root.appendingPathComponent("论文 sample.pdf")
        try Self.makePDF(pdf)
        let service = PDFConversionService(environment: environment)
        let converted = try await service.convert(pdf) { print("PDF convert: \($0)") }
        defer { try? FileManager.default.removeItem(at: converted.directory) }
        XCTAssertTrue(converted.preview.contains("Research paper"))
        // CoreText's PDF font map can encode 文 as the visually equivalent Kangxi
        // radical ⽂. Verify text retention without changing the converter's output.
        XCTAssertTrue(converted.preview.precomposedStringWithCompatibilityMapping.contains("中文"))
        XCTAssertFalse(converted.manifest.images.isEmpty)
        XCTAssertTrue(converted.manifest.failedPages.isEmpty)
        let export = try PDFConversionService.export(converted, to: root, name: "converted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        let partial = root.appendingPathComponent("partial")
        let script = """
        import runpy, sys
        from unittest.mock import patch
        from pathlib import Path
        worker = runpy.run_path(sys.argv[1])
        with patch('pdfplumber.page.Page.to_image', side_effect=RuntimeError('simulated image failure')):
            worker['convert'](Path(sys.argv[2]), Path(sys.argv[3]))
        """
        _ = try await PDFProcessRunner().run(environment.python, arguments: ["-I", "-c", script,
            try PDFConversionEnvironment.resource("convert.py").path, pdf.path, partial.path])
        let partialManifest = try JSONDecoder().decode(PDFConversionResult.Manifest.self,
            from: Data(contentsOf: partial.appendingPathComponent("result.json")))
        XCTAssertEqual(partialManifest.failedPages, [1])
        XCTAssertTrue(partialManifest.images.isEmpty)
        XCTAssertTrue(try String(contentsOf: partial.appendingPathComponent("body.md"), encoding: .utf8).contains("Research paper"))
        for kind in ["scan", "rotated", "columns", "table"] {
            let fixture = root.appendingPathComponent("\(kind).pdf")
            try Self.makePDF(fixture, kind: kind)
            let output = try await service.convert(fixture) { _ in }
            defer { try? FileManager.default.removeItem(at: output.directory) }
            if kind == "scan" {
                XCTAssertTrue(output.manifest.emptyText)
                XCTAssertFalse(output.manifest.images.isEmpty)
            } else {
                XCTAssertFalse(output.manifest.emptyText)
            }
            if kind == "rotated" { XCTAssertFalse(output.manifest.images.isEmpty) }
            if kind == "columns" {
                XCTAssertTrue(output.preview.contains("Left column"))
                XCTAssertTrue(output.preview.contains("Right column"))
            }
            if kind == "table" { XCTAssertTrue(output.preview.contains("Value")) }
            print("PDF fixture \(kind): \(output.preview.count) characters, \(output.manifest.images.count) images; output: \(output.preview.prefix(160))")
        }
        let broken = root.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: broken)
        do { _ = try await service.convert(broken) { _ in }; XCTFail("Invalid PDF accepted") } catch { }
        let locked = try XCTUnwrap(PDFDocument(url: pdf))
        let lockedURL = root.appendingPathComponent("locked.pdf")
        XCTAssertTrue(locked.write(to: lockedURL, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        do { _ = try await service.convert(lockedURL) { _ in }; XCTFail("Locked PDF accepted") } catch {
            XCTAssertEqual(error.localizedDescription, AppLocalizer.string("pdf.error.locked"))
        }
    }

    private static func makePDF(_ url: URL, kind: String = "ordinary") throws {
        var box = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        func text(_ value: String, x: CGFloat, y: CGFloat) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 18)]))
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }
        if kind != "scan" { text("Research paper 中文论文", x: 40, y: 740) }
        if kind == "columns" {
            for row in 0..<5 {
                text("Left column \(row)", x: 40, y: CGFloat(700 - row * 25))
                text("Right column \(row)", x: 320, y: CGFloat(700 - row * 25))
            }
        }
        if kind == "table" {
            for (row, values) in [["Name", "Value", "Unit"], ["A", "10", "m"], ["B", "20", "s"]].enumerated() {
                for (column, value) in values.enumerated() { text(value, x: CGFloat(40 + column * 150), y: CGFloat(700 - row * 30)) }
            }
        }
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0, green: 0.3, blue: 0.8, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.draw(try XCTUnwrap(bitmap.makeImage()), in: CGRect(x: 40, y: 500, width: 100, height: 100))
        context.endPDFPage()
        context.closePDF()
        if kind == "rotated" {
            let document = try XCTUnwrap(PDFDocument(url: url))
            document.page(at: 0)?.rotation = 90
            XCTAssertTrue(document.write(to: url))
        }
    }
}
