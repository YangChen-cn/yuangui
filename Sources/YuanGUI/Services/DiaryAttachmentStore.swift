import AppKit
import Foundation

/// 日记附件存储服务
final class DiaryAttachmentStore: Sendable {
    private let attachmentsURL: URL
    private let thumbnailsURL: URL

    init(baseURL: URL) {
        self.attachmentsURL = baseURL.appendingPathComponent("Attachments", isDirectory: true)
        self.thumbnailsURL = attachmentsURL.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// 保存图片附件（生成 UUID 文件名 + 缩略图）
    func saveImage(data: Data, originalName: String) throws -> DiaryAttachment {
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)

        let ext = (originalName as NSString).pathExtension.lowercased()
        let filename = UUID().uuidString + "." + (ext.isEmpty ? "jpg" : ext)
        let fileURL = attachmentsURL.appendingPathComponent(filename)
        try data.write(to: fileURL)

        // 生成缩略图
        if let image = NSImage(data: data) {
            let thumbData = generateThumbnail(image: image)
            let thumbURL = thumbnailsURL.appendingPathComponent(
                (filename as NSString).deletingPathExtension + ".thumb.jpg"
            )
            try thumbData.write(to: thumbURL)
        }

        let mimeType: String
        switch ext {
        case "png":  mimeType = "image/png"
        case "gif":  mimeType = "image/gif"
        case "webp": mimeType = "image/webp"
        case "heic": mimeType = "image/heic"
        default:     mimeType = "image/jpeg"
        }

        return DiaryAttachment(
            filename: filename,
            originalFilename: originalName,
            mimeType: mimeType
        )
    }

    /// 加载附件数据
    func load(attachment: DiaryAttachment) throws -> Data {
        let url = attachmentsURL.appendingPathComponent(attachment.filename)
        return try Data(contentsOf: url)
    }

    /// 加载缩略图
    func loadThumbnail(attachment: DiaryAttachment) throws -> Data? {
        let url = thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// 清理无引用附件（传入所有有效附件文件名集合）
    func cleanup(usedFilenames: Set<String>) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: attachmentsURL,
            includingPropertiesForKeys: nil
        )
        for file in files {
            let name = file.lastPathComponent
            if !usedFilenames.contains(name) {
                try FileManager.default.removeItem(at: file)
                // 同步删除缩略图
                let thumbURL = thumbnailsURL.appendingPathComponent(
                    (name as NSString).deletingPathExtension + ".thumb.jpg"
                )
                if FileManager.default.fileExists(atPath: thumbURL.path) {
                    try FileManager.default.removeItem(at: thumbURL)
                }
            }
        }
    }

    /// 获取附件完整路径
    func path(for attachment: DiaryAttachment) -> URL {
        attachmentsURL.appendingPathComponent(attachment.filename)
    }

    // MARK: - Private

    private func generateThumbnail(image: NSImage) -> Data {
        let maxSize: CGFloat = 200
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Data()
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(maxSize / width, maxSize / height, 1.0)
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let thumbnail = context.makeImage() else { return Data() }
        let rep = NSBitmapImageRep(cgImage: thumbnail)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) ?? Data()
    }
}
