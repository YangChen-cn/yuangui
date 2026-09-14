import Foundation
import UniformTypeIdentifiers
import ImageIO

enum DocumentInput: Equatable {
    case pdf, xps, ebook, text, image
    static let extensions = ["pdf", "xps", "epub", "fb2", "txt", "png", "jpg", "jpeg", "tif", "tiff"]
    static var contentTypes: [UTType] { extensions.compactMap { UTType(filenameExtension: $0) } }
    init?(url: URL) {
        guard url.isFileURL else { return nil }
        switch url.pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "xps": self = .xps
        case "epub", "fb2": self = .ebook
        case "txt": self = .text
        case "png", "jpg", "jpeg", "tif", "tiff": self = .image
        default: return nil
        }
    }
    var needsRuntime: Bool { self != .text && self != .image }
    var showsPageOptions: Bool { self == .pdf || self == .xps }
}

/// Images use the same native Vision service as screenshot OCR. Text needs no model.
struct NativeDocumentConversionService: Sendable {
    var ocr: any OCRTextRecognizing = VisionOCRService()
    var temporaryRoot: URL = FileManager.default.temporaryDirectory
    func convert(_ source: URL, progress: @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let directory = temporaryRoot.appendingPathComponent("YuanGUI-Document-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        let bodyURL = directory.appendingPathComponent("body.md")
        if DocumentInput(url: source) == .text {
            await progress("text")
            let data = try Data(contentsOf: source)
            let text: String?
            if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { text = String(data: data, encoding: .utf16) }
            else { text = String(data: data, encoding: .utf8) }
            guard let text else { throw PDFConversionError.message("document.error.encoding") }
            try Task.checkCancellation()
            try Data(text.utf8).write(to: bodyURL)
        } else {
            guard DocumentInput(url: source) == .image,
                  let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw PDFConversionError.message("pdf.error.invalid") }
            await progress("imageOCR")
            FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
            let file = try FileHandle(forWritingTo: bodyURL)
            defer { try? file.close() }
            for page in 0..<CGImageSourceGetCount(imageSource) {
                try Task.checkCancellation()
                // Decode one correctly oriented frame at a time; TIFF may contain many.
                guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, page, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3200
                ] as CFDictionary) else { throw PDFConversionError.message("pdf.error.invalid") }
                let text = try await ocr.recognizeText(in: image)
                try Task.checkCancellation()
                if page > 0 { try file.write(contentsOf: Data("\n\n".utf8)) }
                try file.write(contentsOf: Data(text.utf8))
            }
        }
        try Task.checkCancellation()
        let (preview, truncated) = try PDFConversionService.readPreview(bodyURL)
        let result = PDFConversionResult(directory: directory, manifest: .init(images: [], emptyText: preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), preview: preview, truncated: truncated)
        completed = true
        return result
    }
}
