import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreText
@testable import YuanGUI

private struct DocumentFixtureOCR: OCRTextRecognizing {
    var delay = false
    func recognizeText(in image: CGImage) async throws -> String {
        if delay { try? await Task.sleep(for: .milliseconds(150)) }
        return "识别的文字 Recognized text"
    }
}

final class DocumentConversionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testFormatRoutingAndOptions() {
        for ext in DocumentInput.extensions {
            let kind = DocumentInput(url: root.appendingPathComponent("test.\(ext.uppercased())"))
            XCTAssertNotNil(kind)
            XCTAssertEqual(kind?.showsPageOptions, ["pdf", "xps"].contains(ext))
            XCTAssertEqual(kind?.needsRuntime, ["pdf", "xps", "epub", "fb2"].contains(ext))
        }
        XCTAssertNil(DocumentInput(url: root.appendingPathComponent("unverified.mobi")))
        XCTAssertNil(DocumentInput(url: URL(string: "https://example.com/test.pdf")!))
        XCTAssertNil(DocumentInput(url: root.appendingPathComponent("unsupported.docx")))
    }
    func testTextNeedsNoRuntimeAndExportsFullUnicodeBody() async throws {
        let original = String(repeating: "中文 😀 text\n", count: 30_000)
        for encoding in [String.Encoding.utf8, .utf16] {
            let source = root.appendingPathComponent("文字 \(encoding.rawValue).txt")
            try original.data(using: encoding)!.write(to: source)
            let output = try await NativeDocumentConversionService(temporaryRoot: root).convert(source) { _ in }
            XCTAssertTrue(output.truncated)
            XCTAssertEqual(output.preview.count, 200_000)
            XCTAssertTrue(output.manifest.images.isEmpty)
            let exported = try PDFConversionService.export(output, to: root, name: "export")
            XCTAssertEqual(try String(contentsOf: exported, encoding: .utf8), original)
        }
    }
    func testImageFormatsAndAllTIFFFramesUseInjectedVisionInterface() async throws {
        for type in [UTType.png, .jpeg, .tiff] {
            let file = try makeImage(type: type, frames: type == .tiff ? 2 : 1)
            let editorImage = try ScreenshotImageLoader.load(file)
            XCTAssertEqual(editorImage.width, 800)
            XCTAssertEqual(editorImage.height, 200)
            let result = try await NativeDocumentConversionService(ocr: DocumentFixtureOCR(), temporaryRoot: root).convert(file) { _ in }
            XCTAssertEqual(result.preview.components(separatedBy: "Recognized text").count - 1, type == .tiff ? 2 : 1)
            XCTAssertFalse(result.manifest.emptyText)
        }
    }
    func testNativeOCRCancellationDiscardsLateResultsAndTemporaryFiles() async throws {
        let file = try makeImage(type: .png, frames: 1)
        let service = NativeDocumentConversionService(ocr: DocumentFixtureOCR(delay: true), temporaryRoot: root)
        let task = Task { try await service.convert(file) { _ in } }
        try await Task.sleep(for: .milliseconds(40))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled OCR result was published") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
    }
    func testNativeVisionRecognizesActualImageText() async throws {
        for type in [UTType.png, .jpeg, .tiff] {
            let source = try makeImage(type: type, frames: type == .tiff ? 2 : 1, text: "Native OCR 中文识别")
            let result = try await NativeDocumentConversionService(temporaryRoot: root).convert(source) { _ in }
            XCTAssertTrue(result.preview.lowercased().contains("native ocr"), result.preview)
            XCTAssertTrue(result.preview.contains("中文"), result.preview)
            XCTAssertFalse(result.manifest.emptyText)
        }
    }
    @MainActor func testTextCanConvertBeforeRuntimeInstallationAndEbooksHidePDFOptions() async throws {
        let source = root.appendingPathComponent("source.txt")
        try Data("local text".utf8).write(to: source)
        let defaults = UserDefaults(suiteName: "DocumentTest-\(UUID())")!
        let store = PDFConversionStore(environment: PDFConversionEnvironment(root: root.appendingPathComponent("missing-runtime")), defaults: defaults)
        store.select([source])
        XCTAssertFalse(store.isReady); XCTAssertTrue(store.canConvert)
        store.convert()
        for _ in 0..<100 where store.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.result?.preview, "local text")
        XCTAssertFalse(store.ocrApplied)
        store.select([root.appendingPathComponent("book.epub")])
        XCTAssertFalse(store.canConvert); XCTAssertEqual(store.inputKind, .ebook)
        store.close()
    }
    private func makeImage(type: UTType, frames: Int, text: String? = nil) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 800, height: 200))
        if let text {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black]))
            context.textPosition = CGPoint(x: 30, y: 90)
            CTLineDraw(line, context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let file = root.appendingPathComponent("image.\(type.preferredFilenameExtension!)")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return file
    }
}
