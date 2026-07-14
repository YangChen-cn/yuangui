import AppKit
import Foundation
import PDFKit

protocol AttachmentPreparing {
    func prepare(url: URL) throws -> PreparedChatAttachment
}

struct AttachmentPreparer: AttachmentPreparing {
    static let maximumBytes: Int64 = 20 * 1_024 * 1_024
    static let maximumCharacters = 50_000
    private let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "csv", "tsv", "log", "xml", "yaml", "yml",
        "swift", "m", "mm", "h", "c", "cpp", "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "java", "kt", "sh", "zsh", "html", "css", "sql"
    ]
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]

    func prepare(url: URL) throws -> PreparedChatAttachment {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ChatServiceError.unreadableAttachment(url.lastPathComponent) }
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= Self.maximumBytes else { throw ChatServiceError.attachmentTooLarge(url.lastPathComponent) }
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return try prepareImage(url: url, byteCount: byteCount) }
        if ext == "pdf" { return try preparePDF(url: url, byteCount: byteCount) }
        if textExtensions.contains(ext) { return try prepareText(url: url, byteCount: byteCount) }
        throw ChatServiceError.unsupportedAttachment(url.lastPathComponent)
    }

    private func prepareImage(url: URL, byteCount: Int64) throws -> PreparedChatAttachment {
        guard let image = NSImage(contentsOf: url),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ChatServiceError.unreadableAttachment(url.lastPathComponent)
        }
        let maximum: CGFloat = 2_048
        let scale = min(1, maximum / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ChatServiceError.unreadableAttachment(url.lastPathComponent) }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { throw ChatServiceError.unreadableAttachment(url.lastPathComponent) }
        let representation = NSBitmapImageRep(cgImage: resized)
        guard let data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw ChatServiceError.unreadableAttachment(url.lastPathComponent)
        }
        let metadata = ChatAttachmentMetadata(name: url.lastPathComponent, kind: .image, byteCount: byteCount)
        return PreparedChatAttachment(metadata: metadata, payload: .imageDataURL("data:image/jpeg;base64,\(data.base64EncodedString())"))
    }

    private func preparePDF(url: URL, byteCount: Int64) throws -> PreparedChatAttachment {
        guard let document = PDFDocument(url: url), let content = document.string, !content.isEmpty else {
            throw ChatServiceError.unreadableAttachment(url.lastPathComponent)
        }
        return extracted(content, url: url, kind: .pdf, byteCount: byteCount)
    }

    private func prepareText(url: URL, byteCount: Int64) throws -> PreparedChatAttachment {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ChatServiceError.unreadableAttachment(url.lastPathComponent)
        }
        return extracted(content, url: url, kind: .text, byteCount: byteCount)
    }

    private func extracted(_ content: String, url: URL, kind: ChatAttachmentMetadata.Kind, byteCount: Int64) -> PreparedChatAttachment {
        let truncated = content.count > Self.maximumCharacters
        let text = truncated ? String(content.prefix(Self.maximumCharacters)) : content
        let metadata = ChatAttachmentMetadata(
            name: url.lastPathComponent,
            kind: kind,
            byteCount: byteCount,
            wasTruncated: truncated
        )
        return PreparedChatAttachment(metadata: metadata, payload: .extractedText(text))
    }
}
