import XCTest
import AppKit
import PDFKit
@testable import YuanGUI

private actor OptionsRecorder {
    private(set) var values: [PDFConversionOptions] = []
    func record(_ value: PDFConversionOptions) { values.append(value) }
}

final class PDFConversionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func result(body: String = "中文 **paper**", images: [String] = []) throws -> PDFConversionResult {
        let work = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: work.appendingPathComponent("body.md"))
        return PDFConversionResult(directory: work,
            manifest: .init(images: images, emptyText: body.isEmpty), preview: body, truncated: false)
    }

    func testExportRewritesPictureLinksAndNeverOverwritesEitherExistingName() throws {
        let body = "中文 **paper**\n\n![](\(PDFConversionService.assetsDirectory)/figure-0001-01.png)\ntail"
        let converted = try result(body: body, images: ["figure-0001-01.png"])
        try Data([1, 2, 3]).write(to: converted.directory.appendingPathComponent("figure-0001-01.png"))
        let existing = root.appendingPathComponent("论文 paper.md")
        try Data("keep".utf8).write(to: existing)
        let first = try PDFConversionService.export(converted, to: root, name: "论文 paper")
        XCTAssertEqual(first.lastPathComponent, "论文 paper (1).md")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep")
        let markdown = try String(contentsOf: first, encoding: .utf8)
        XCTAssertTrue(markdown.hasPrefix("中文 **paper**"))
        // No temporary path, and no link left pointing at the preview-time folder.
        XCTAssertFalse(markdown.contains("](\(PDFConversionService.assetsDirectory)/"))
        XCTAssertTrue(markdown.contains("(%E8%AE%BA%E6%96%87%20paper%20(1)_assets/figure-0001-01.png)"))
        XCTAssertTrue(markdown.hasSuffix("tail"))
        let image = root.appendingPathComponent("论文 paper (1)_assets/figure-0001-01.png")
        XCTAssertEqual(try Data(contentsOf: image), Data([1, 2, 3]))
        let second = try PDFConversionService.export(converted, to: root, name: "论文 paper")
        XCTAssertEqual(second.lastPathComponent, "论文 paper (2).md")
    }

    func testExportFailureCleansStagingAndPreservesOtherFiles() throws {
        let converted = try result(images: ["missing.png"])
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

    func testStaleRuntimeCleanupKeepsTheCurrentRevisionAndUnrelatedFiles() throws {
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent("runtime-root"))
        let fm = FileManager.default
        try fm.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        let stale = environment.root.appendingPathComponent("markitdown-0.1.7-v1")
        let unrelatedFolder = environment.root.appendingPathComponent("notes")
        let hiddenFolder = environment.root.appendingPathComponent(".hidden-v1")
        for folder in [stale, unrelatedFolder, hiddenFolder] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let file = environment.root.appendingPathComponent("keep-v1.txt")
        try Data("keep".utf8).write(to: file)
        // An older install, and one a newer app version could own.
        let older = Date(timeIntervalSince1970: 1_000_000)
        try fm.setAttributes([.modificationDate: older], ofItemAtPath: stale.path)
        try fm.setAttributes([.modificationDate: older.addingTimeInterval(3600)], ofItemAtPath: environment.directory.path)
        environment.removeStaleRevisions()
        XCTAssertFalse(fm.fileExists(atPath: stale.path), "An installed revision replaces earlier ones")
        XCTAssertTrue(fm.fileExists(atPath: environment.directory.path), "The current revision survives")
        XCTAssertTrue(fm.fileExists(atPath: unrelatedFolder.path))
        XCTAssertTrue(fm.fileExists(atPath: file.path))
        XCTAssertTrue(fm.fileExists(atPath: hiddenFolder.path))
        // A newer app version may own a revision this build knows nothing about.
        let newer = environment.root.appendingPathComponent("pymupdf-layout-2.0.0-v1")
        try fm.createDirectory(at: newer, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: older.addingTimeInterval(7200)], ofItemAtPath: newer.path)
        environment.removeStaleRevisions()
        XCTAssertTrue(fm.fileExists(atPath: newer.path))
    }

    /// A ready-looking runtime with a known payload, used by the size and removal tests.
    private func installedEnvironment(_ name: String, payload: Int = 3) throws -> (PDFConversionEnvironment, Int64) {
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent(name))
        let fm = FileManager.default
        try fm.createDirectory(at: environment.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: environment.python)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: environment.python.path)
        try Data(Self.revisionMarker.utf8).write(to: environment.directory.appendingPathComponent("ready"))
        // The ready marker is part of the installed payload the size walk reports.
        var bytes = Int64(Self.revisionMarker.utf8.count)
        for index in 0..<payload {
            let file = environment.directory.appendingPathComponent("payload-\(index).bin")
            try Data(repeating: 0, count: 4096 + index).write(to: file)
            bytes += Int64(4096 + index)
        }
        return (environment, bytes)
    }

    private static let revisionMarker = "pymupdf-layout-1.28.2-ocr-v1"

    func testSizeOnDiskCountsTheInstalledRuntime() throws {
        let (environment, payload) = try installedEnvironment("size")
        XCTAssertTrue(environment.isReady)
        XCTAssertEqual(environment.sizeOnDisk(), payload)
        let missing = PDFConversionEnvironment(root: root.appendingPathComponent("absent"))
        XCTAssertEqual(missing.sizeOnDisk(), 0)
        XCTAssertFalse(missing.isReady)
    }

    func testUninstallRemovesOnlyThisRuntime() async throws {
        let (environment, _) = try installedEnvironment("uninstall")
        let neighbour = root.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: neighbour)
        try environment.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.root.path))
        XCTAssertFalse(environment.isReady)
        XCTAssertEqual(environment.sizeOnDisk(), 0)
        XCTAssertEqual(try String(contentsOf: neighbour, encoding: .utf8), "keep")
    }

    func testUninstallRefusesWhileAnotherInstallerHoldsTheLock() async throws {
        let (environment, payload) = try installedEnvironment("locked-uninstall")
        let descriptor = Darwin.open(environment.root.appendingPathComponent(".install-lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        do { try environment.uninstall(); XCTFail("The lock must protect the runtime") }
        catch { XCTAssertEqual(error.localizedDescription, AppLocalizer.string("pdf.error.busy")) }
        XCTAssertEqual(environment.sizeOnDisk(), payload)
    }

    /// The installer may only delete files the pinned engine never reads.
    func testRemovingUnusedFilesKeepsWhatTheEngineLoads() throws {
        let (environment, _) = try installedEnvironment("prune")
        let site = environment.directory.appendingPathComponent("venv/lib/python3.12/site-packages")
        let models = site.appendingPathComponent("pymupdf/layout/resources/onnx")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        let kept = ["layout_rf2.4.1+imf1.onnx", "layout_rf2.4.1+imf1.yaml", "feature_imf1.onnx", "table_grid_model_v4_ep.onnx"]
        let unused = ["layout_imf1.onnx", "layout_rf2.4.1.onnx", "table_grid_model_v2c.onnx", "table_grid_model_v1t.onnx"]
        for name in kept + unused {
            try Data(repeating: 1, count: 1024).write(to: models.appendingPathComponent(name))
        }
        let tools = ["sympy", "mpmath", "networkx", "onnxruntime/tools", "onnxruntime/transformers", "onnxruntime/quantization"]
        for name in tools {
            let folder = site.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 2, count: 2048).write(to: folder.appendingPathComponent("module.py"))
        }
        // OpenCV, Pillow and PyYAML are needed by the optional OCR pass and must survive.
        let ocr = site.appendingPathComponent("cv2/__init__.py")
        try FileManager.default.createDirectory(at: ocr.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: ocr)
        let removed = environment.removeUnusedFiles()
        XCTAssertGreaterThanOrEqual(removed, Int64(unused.count * 1024 + tools.count * 2048))
        for name in kept { XCTAssertTrue(FileManager.default.fileExists(atPath: models.appendingPathComponent(name).path), name) }
        for name in unused { XCTAssertFalse(FileManager.default.fileExists(atPath: models.appendingPathComponent(name).path), name) }
        for name in tools { XCTAssertFalse(FileManager.default.fileExists(atPath: site.appendingPathComponent(name).path), name) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ocr.path))
    }

    @MainActor
    func testUninstallResetsTheWindowState() async throws {
        let (environment, _) = try installedEnvironment("store-uninstall")
        let store = PDFConversionStore(environment: environment, uninstall: { try environment.uninstall() })
        XCTAssertTrue(store.isReady)
        store.uninstall()
        await drain(store)
        XCTAssertFalse(store.isReady)
        XCTAssertEqual(store.runtimeBytes, 0)
        XCTAssertEqual(store.stage, "uninstalled")
        XCTAssertNil(store.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.root.path))
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
            let store = PDFConversionStore(environment: environment, convert: { _, _, _ in
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

    /// Window options must reach the worker as command line flags, and nothing else.
    func testWorkerFlagsFollowTheWindowOptions() async throws {
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent("fake"))
        try FileManager.default.createDirectory(at: environment.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: environment.directory.appendingPathComponent("ready"))
        let log = root.appendingPathComponent("arguments.txt")
        // Stand in for the installed Python: record the arguments and write a minimal result.
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(log.path)"
        mkdir -p "$4"
        printf 'text' > "$4/body.md"
        printf '{"images":[],"emptyText":false}' > "$4/result.json"
        """
        try Data(script.utf8).write(to: environment.python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: environment.python.path)
        let source = root.appendingPathComponent("paper.pdf")
        try Data("pdf".utf8).write(to: source)
        let service = PDFConversionService(environment: environment)
        let cases: [(options: PDFConversionOptions, flags: Set<String>)] = [
            (PDFConversionOptions(useOCR: false, removeHeaderFooter: true), []),
            (PDFConversionOptions(useOCR: true, removeHeaderFooter: false), ["--ocr", "--keep-header-footer"])
        ]
        for testCase in cases {
            let converted = try await service.convert(source, options: testCase.options) { _ in }
            defer { try? FileManager.default.removeItem(at: converted.directory) }
            let arguments = try String(contentsOf: log, encoding: .utf8)
            XCTAssertTrue(arguments.hasPrefix("-I\n"), "convert.py must not run with the user's Python startup paths")
            for flag in ["--ocr", "--keep-header-footer"] {
                XCTAssertEqual(arguments.contains(flag), testCase.flags.contains(flag), flag)
            }
            XCTAssertEqual(converted.preview, "text")
        }
    }

    /// The probe runs before the Layout model and must survive the worker's JSON channel.
    func testProbeReportsDocumentFacts() async throws {
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent("probe"))
        try FileManager.default.createDirectory(at: environment.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: environment.directory.appendingPathComponent("ready"))
        let script = """
        #!/bin/sh
        printf '%s\\n' '{"probe": {"pages": 405, "encrypted": false, "textPages": 0, "sampledPages": 5, "scanned": true}}'
        """
        try Data(script.utf8).write(to: environment.python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: environment.python.path)
        let source = root.appendingPathComponent("scan.pdf")
        try Data("pdf".utf8).write(to: source)
        let probe = try await PDFConversionService(environment: environment).probe(source)
        XCTAssertEqual(probe, PDFProbe(pages: 405, encrypted: false, textPages: 0, sampledPages: 5, scanned: true))
    }

    @MainActor
    func testOptionDefaultsPersistAndDriveConversion() async throws {
        let suite = "PDFConversionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent("toggle"))
        try FileManager.default.createDirectory(at: environment.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: environment.python, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        try Data().write(to: environment.directory.appendingPathComponent("ready"))
        let recorded = OptionsRecorder()
        let defaultResult = try result()
        let changedResult = try result()
        let store = PDFConversionStore(environment: environment, defaults: defaults, convert: { _, options, _ in
            await recorded.record(options)
            return options.useOCR ? changedResult : defaultResult
        })
        store.select([root.appendingPathComponent("paper.pdf")])
        XCTAssertTrue(store.ocrEnabled, "Hybrid OCR is on by default")
        XCTAssertTrue(store.removeHeaderFooter, "Repeated headers and footers are dropped by default")
        store.convert()
        await drain(store)
        XCTAssertTrue(store.ocrApplied)
        store.setOCR(false)
        store.setRemoveHeaderFooter(false)
        XCTAssertFalse(defaults.bool(forKey: "pdf.ocrEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "pdf.removeHeaderFooter"))
        store.convert()
        await drain(store)
        XCTAssertFalse(store.ocrApplied)
        let reopened = PDFConversionStore(environment: environment, defaults: defaults)
        XCTAssertFalse(reopened.ocrEnabled, "An explicit choice survives the new default")
        XCTAssertFalse(reopened.removeHeaderFooter)
        let recordedOptions = await recorded.values
        XCTAssertEqual(recordedOptions, [PDFConversionOptions(), PDFConversionOptions(useOCR: false, removeHeaderFooter: false)])
    }

    @MainActor
    func testProbeDrivesScannedHintAndLockedError() async throws {
        let environment = PDFConversionEnvironment(root: root.appendingPathComponent("hint"))
        try FileManager.default.createDirectory(at: environment.python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: environment.python, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        try Data().write(to: environment.directory.appendingPathComponent("ready"))
        let locked = PDFProbe(pages: 2, encrypted: true, textPages: 0, sampledPages: 0, scanned: false)
        let store = PDFConversionStore(environment: environment, probe: { _ in locked })
        store.select([root.appendingPathComponent("paper.pdf")])
        for _ in 0..<200 {
            if store.probe != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.probe, locked)
        XCTAssertEqual(store.error, AppLocalizer.string("pdf.error.locked"))
        // Selecting another document clears the previous verdict.
        store.select([root.appendingPathComponent("other.pdf")])
        XCTAssertNil(store.probe)
        XCTAssertNil(store.error)
    }

    @MainActor
    private func drain(_ store: PDFConversionStore) async {
        for _ in 0..<200 {
            if !store.isBusy { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isBusy)
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
        // The installer keeps only what the conversion path reads.
        let site = environment.directory.appendingPathComponent("venv/lib/python3.12/site-packages")
        for relative in ["uv-aarch64-apple-darwin", "sympy", "mpmath", "networkx",
                         "venv/lib/python3.12/site-packages/onnxruntime/tools"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: environment.directory.appendingPathComponent(relative).path), relative)
        }
        let models = site.appendingPathComponent("pymupdf/layout/resources/onnx")
        for name in ["layout_rf2.4.1+imf1.onnx", "layout_rf2.4.1+imf1.yaml", "feature_imf1.onnx", "table_grid_model_v4_ep.onnx"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: models.appendingPathComponent(name).path), name)
        }
        for name in ["layout_imf1.onnx", "layout_rf2.4.1.onnx", "table_grid_model_v4.onnx", "table_grid_model_v2c.onnx"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: models.appendingPathComponent(name).path), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: site.appendingPathComponent("pymupdf/mupdf-devel").path), "mupdf-devel")
        let installedBytes = environment.sizeOnDisk()
        print("PDF runtime size: \(installedBytes / 1_048_576) MB")
        XCTAssertGreaterThan(installedBytes, 100 * 1_048_576)
        XCTAssertLessThan(installedBytes, 420 * 1_048_576, "Pruned runtime must stay well under the unpruned 490 MB")
        // A second install is a read-only fast path.
        try await environment.install { _ in XCTFail("Ready environment should not reinstall") }
        let pdf = root.appendingPathComponent("论文 sample.pdf")
        try Self.makePDF(pdf)
        let service = PDFConversionService(environment: environment)
        let probed = try await service.probe(pdf)
        XCTAssertEqual(probed.pages, 1)
        XCTAssertFalse(probed.encrypted)
        XCTAssertFalse(probed.scanned)
        let converted = try await service.convert(pdf, options: PDFConversionOptions()) { print("PDF convert: \($0)") }
        defer { try? FileManager.default.removeItem(at: converted.directory) }
        XCTAssertTrue(converted.preview.contains("Research paper"))
        // CoreText's PDF font map can encode 文 as the visually equivalent Kangxi
        // radical ⽂. Verify text retention without changing the converter's output.
        XCTAssertTrue(converted.preview.precomposedStringWithCompatibilityMapping.contains("中文"))
        XCTAssertFalse(converted.manifest.images.isEmpty)
        // Pictures stay next to their position in the text and are named for export.
        for image in converted.manifest.images {
            XCTAssertTrue(FileManager.default.fileExists(atPath: converted.directory.appendingPathComponent(image).path))
            XCTAssertTrue(converted.preview.contains("](\(PDFConversionService.assetsDirectory)/\(image))"), image)
            XCTAssertFalse(converted.preview.contains("/private/"), "No temporary path may reach the Markdown")
        }
        let export = try PDFConversionService.export(converted, to: root, name: "converted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        let exported = try String(contentsOf: export, encoding: .utf8)
        XCTAssertFalse(exported.contains("](\(PDFConversionService.assetsDirectory)/"))
        let firstImage = try XCTUnwrap(converted.manifest.images.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("converted_assets/\(firstImage)").path))
        // Repeated page headers and footers are dropped by default and kept on request.
        let running = root.appendingPathComponent("running.pdf")
        try Self.makeRunningHeaderPDF(running)
        let trimmed = try await service.convert(running, options: PDFConversionOptions()) { _ in }
        defer { try? FileManager.default.removeItem(at: trimmed.directory) }
        XCTAssertFalse(trimmed.preview.contains("Datasheet KV-2400"))
        XCTAssertFalse(trimmed.preview.contains("Page 1 of 3"))
        XCTAssertTrue(trimmed.preview.contains("Section body text"))
        let kept = try await service.convert(running, options: PDFConversionOptions(removeHeaderFooter: false)) { _ in }
        defer { try? FileManager.default.removeItem(at: kept.directory) }
        XCTAssertTrue(kept.preview.contains("Datasheet KV-2400"))
        let scannedText = root.appendingPathComponent("扫描文字 OCR.pdf")
        let rasterize = """
        import pymupdf, sys
        with pymupdf.open(sys.argv[1]) as original, pymupdf.open() as scanned:
            page = original[0]
            scanned.new_page(width=page.rect.width, height=page.rect.height).insert_image(
                page.rect, pixmap=page.get_pixmap(matrix=pymupdf.Matrix(2, 2)))
            scanned.save(sys.argv[2])
        """
        _ = try await PDFProcessRunner().run(environment.python, arguments: ["-I", "-c", rasterize, pdf.path, scannedText.path])
        let scannedProbe = try await service.probe(scannedText)
        XCTAssertTrue(scannedProbe.scanned, "A rasterized page has no text layer to offer")
        XCTAssertEqual(scannedProbe.textPages, 0)
        let textOnly = try await service.convert(
            scannedText, options: PDFConversionOptions(useOCR: false)) { _ in }
        defer { try? FileManager.default.removeItem(at: textOnly.directory) }
        // With OCR switched off there is no text layer to extract from the rasterized page.
        XCTAssertFalse(textOnly.preview.lowercased().contains("research paper"))
        // The default is hybrid OCR, which recognizes such a page.
        let recognized = try await service.convert(scannedText, options: PDFConversionOptions()) { _ in }
        defer { try? FileManager.default.removeItem(at: recognized.directory) }
        XCTAssertTrue(recognized.preview.lowercased().contains("research paper"))
        XCTAssertTrue(recognized.preview.contains("中文"))
        XCTAssertFalse(recognized.manifest.emptyText)
        for kind in ["ordinary", "scan", "rotated", "columns", "table"] {
            let fixture = root.appendingPathComponent("\(kind).pdf")
            try Self.makePDF(fixture, kind: kind)
            let output = try await service.convert(fixture, options: PDFConversionOptions()) { _ in }
            defer { try? FileManager.default.removeItem(at: output.directory) }
            if kind == "scan" {
                XCTAssertTrue(output.manifest.emptyText)
            } else {
                XCTAssertFalse(output.manifest.emptyText)
            }
            if kind == "rotated" { XCTAssertFalse(output.manifest.images.isEmpty) }
            if kind == "ordinary" { XCTAssertFalse(output.manifest.images.isEmpty, "The bitmap must survive as a picture") }
            if kind == "columns" {
                XCTAssertTrue(output.preview.contains("Left column"))
                XCTAssertTrue(output.preview.contains("Right column"))
            }
            if kind == "table" { XCTAssertTrue(output.preview.contains("Value")) }
            print("PDF fixture \(kind): \(output.preview.count) characters, \(output.manifest.images.count) images; output: \(output.preview.prefix(160))")
        }
        let broken = root.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: broken)
        do { _ = try await service.convert(broken, options: PDFConversionOptions()) { _ in }; XCTFail("Invalid PDF accepted") } catch { }
        do { _ = try await service.probe(broken); XCTFail("Invalid PDF accepted") } catch { }
        let locked = try XCTUnwrap(PDFDocument(url: pdf))
        let lockedURL = root.appendingPathComponent("locked.pdf")
        XCTAssertTrue(locked.write(to: lockedURL, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        // A locked document is reported without loading the Layout model.
        let lockedProbe = try await service.probe(lockedURL)
        XCTAssertTrue(lockedProbe.encrypted)
        do { _ = try await service.convert(lockedURL, options: PDFConversionOptions()) { _ in }; XCTFail("Locked PDF accepted") } catch {
            XCTAssertEqual(error.localizedDescription, AppLocalizer.string("pdf.error.locked"))
        }
    }

    /// Three pages repeating the same running header and footer, as a datasheet does.
    private static func makeRunningHeaderPDF(_ url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for page in 1...3 {
            context.beginPDFPage(nil)
            func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 18) {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size)]))
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
            }
            text("Datasheet KV-2400", x: 40, y: 770, size: 9)
            text("Page \(page) of 3", x: 40, y: 20, size: 9)
            text("Section body text for page \(page)", x: 40, y: 500)
            for row in 0..<6 { text("Specification line \(row) with details.", x: 40, y: CGFloat(460 - row * 22), size: 12) }
            context.endPDFPage()
        }
        context.closePDF()
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
        if kind != "scan" { text("Research paper 中文论文", x: 40, y: 700) }
        if kind == "ordinary" || kind == "rotated" {
            // Body text below the title, as a real page has. A lone line near the top
            // edge is what the layout model reads as a running page header.
            for row in 0..<6 { text("Body line \(row) of the scheduler notes.", x: 40, y: CGFloat(660 - row * 24)) }
        }
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
        context.draw(try XCTUnwrap(bitmap.makeImage()), in: CGRect(x: 40, y: 360, width: 100, height: 100))
        context.endPDFPage()
        context.closePDF()
        if kind == "rotated" {
            let document = try XCTUnwrap(PDFDocument(url: url))
            document.page(at: 0)?.rotation = 90
            XCTAssertTrue(document.write(to: url))
        }
    }
}
