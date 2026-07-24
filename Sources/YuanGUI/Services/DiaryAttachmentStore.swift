import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct DiaryPreparedImage: Sendable {
    let data: Data
    let originalName: String
    let fileExtension: String
    let mimeType: String
}

struct DiaryImageDataSource: Sendable {
    let data: Data
    let originalName: String
}

struct DiaryImageImportFailure: Identifiable, Equatable, Sendable {
    let name: String
    let message: String
    var id: String { "\(name)-\(message)" }
}

struct DiaryImageImportReport: Sendable {
    let attachments: [DiaryAttachment]
    let failures: [DiaryImageImportFailure]
}

actor DiaryAttachmentStore {
    static let maximumFileSize = 20 * 1_024 * 1_024
    static let maximumPixelCount = 50_000_000
    static let maximumAttachmentsPerEntry = 20

    private let layout: DiaryStorageLayout
    private let fileManager: FileManager
    private let allowedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"])

    init(layout: DiaryStorageLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    init(baseURL: URL) {
        self.init(layout: DiaryStorageLayout(rootURL: baseURL))
    }

    func prepare(urls: [URL], availableSlots: Int) -> (images: [DiaryPreparedImage], failures: [DiaryImageImportFailure]) {
        var images: [DiaryPreparedImage] = []
        var failures: [DiaryImageImportFailure] = []
        let candidates = Array(urls.prefix(max(availableSlots, 0)))
        if urls.count > candidates.count {
            failures.append(DiaryImageImportFailure(name: "所选图片", message: "每篇日记最多添加 \(Self.maximumAttachmentsPerEntry) 张图片"))
        }
        for url in candidates {
            do {
                images.append(try prepare(data: Data(contentsOf: url), originalName: url.lastPathComponent))
            } catch {
                failures.append(DiaryImageImportFailure(name: url.lastPathComponent, message: error.localizedDescription))
            }
        }
        return (images, failures)
    }

    func prepare(data: Data, originalName: String) throws -> DiaryPreparedImage {
        guard !data.isEmpty else { throw DiaryAttachmentError.invalidImage }
        guard data.count <= Self.maximumFileSize else { throw DiaryAttachmentError.fileTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= Self.maximumPixelCount else {
            throw DiaryAttachmentError.invalidDimensions
        }

        let sourceType = CGImageSourceGetType(source) as String?
        let detectedType = sourceType.flatMap(UTType.init)
        let sourceExtension = (originalName as NSString).pathExtension.lowercased()
        let preferredExtension = normalizedExtension(detectedType?.preferredFilenameExtension ?? sourceExtension)
        guard allowedExtensions.contains(preferredExtension), let mimeType = detectedType?.preferredMIMEType ?? mimeType(for: preferredExtension) else {
            throw DiaryAttachmentError.unsupportedFormat
        }
        return DiaryPreparedImage(data: data, originalName: safeOriginalName(originalName), fileExtension: preferredExtension, mimeType: mimeType)
    }

    func save(_ images: [DiaryPreparedImage]) -> DiaryImageImportReport {
        var attachments: [DiaryAttachment] = []
        var failures: [DiaryImageImportFailure] = []
        for image in images {
            do {
                attachments.append(try savePreparedImage(image))
            } catch {
                failures.append(DiaryImageImportFailure(name: image.originalName, message: error.localizedDescription))
            }
        }
        return DiaryImageImportReport(attachments: attachments, failures: failures)
    }

    func saveImage(data: Data, originalName: String) throws -> DiaryAttachment {
        try savePreparedImage(prepare(data: data, originalName: originalName))
    }

    func load(attachment: DiaryAttachment) throws -> Data {
        try validateStoredFilename(attachment.filename)
        return try Data(contentsOf: layout.originalsURL.appendingPathComponent(attachment.filename))
    }

    func loadThumbnail(attachment: DiaryAttachment) throws -> Data? {
        try validateStoredFilename(attachment.filename)
        let url = layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func remove(_ attachment: DiaryAttachment) throws {
        try validateStoredFilename(attachment.filename)
        for url in [
            layout.originalsURL.appendingPathComponent(attachment.filename),
            layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename)
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func cleanup(usedFilenames: Set<String>) throws {
        try prepareDirectories()
        let files = try fileManager.contentsOfDirectory(at: layout.originalsURL, includingPropertiesForKeys: [.isRegularFileKey])
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, !usedFilenames.contains(file.lastPathComponent) else { continue }
            try fileManager.removeItem(at: file)
            let thumbnail = layout.thumbnailsURL.appendingPathComponent((file.lastPathComponent as NSString).deletingPathExtension + ".thumb.jpg")
            try? fileManager.removeItem(at: thumbnail)
        }
    }

    private func savePreparedImage(_ image: DiaryPreparedImage) throws -> DiaryAttachment {
        try prepareDirectories()
        let filename = "\(UUID().uuidString.lowercased()).\(image.fileExtension)"
        try validateStoredFilename(filename)
        let originalURL = layout.originalsURL.appendingPathComponent(filename)
        let thumbnailName = (filename as NSString).deletingPathExtension + ".thumb.jpg"
        let thumbnailURL = layout.thumbnailsURL.appendingPathComponent(thumbnailName)
        do {
            try image.data.write(to: originalURL, options: .atomic)
            let thumbnail = try generateThumbnail(data: image.data)
            try thumbnail.write(to: thumbnailURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: originalURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw error
        }
        return DiaryAttachment(filename: filename, originalFilename: image.originalName, mimeType: image.mimeType)
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: layout.originalsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.thumbnailsURL, withIntermediateDirectories: true)
    }

    private func generateThumbnail(data: Data) throws -> Data {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DiaryAttachmentError.invalidImage
        }
        let maxSize: CGFloat = 240
        let scale = min(maxSize / CGFloat(cgImage.width), maxSize / CGFloat(cgImage.height), 1)
        let width = max(Int(CGFloat(cgImage.width) * scale), 1)
        let height = max(Int(CGFloat(cgImage.height) * scale), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw DiaryAttachmentError.thumbnailFailed }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage(),
              let result = NSBitmapImageRep(cgImage: thumbnail).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            throw DiaryAttachmentError.thumbnailFailed
        }
        return result
    }

    private func validateStoredFilename(_ filename: String) throws {
        guard filename == (filename as NSString).lastPathComponent,
              !filename.contains(".."),
              !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              allowedExtensions.contains((filename as NSString).pathExtension.lowercased()) else {
            throw DiaryAttachmentError.invalidFilename
        }
        let stem = (filename as NSString).deletingPathExtension
        guard UUID(uuidString: stem) != nil else { throw DiaryAttachmentError.invalidFilename }
    }

    private func safeOriginalName(_ name: String) -> String {
        let value = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "图片" : String(value.prefix(255))
    }

    private func normalizedExtension(_ value: String) -> String {
        value.lowercased() == "jpeg" ? "jpg" : value.lowercased()
    }

    private func mimeType(for ext: String) -> String? {
        switch ext {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "heic": "image/heic"
        case "heif": "image/heif"
        case "webp": "image/webp"
        case "gif": "image/gif"
        default: nil
        }
    }
}

enum DiaryAttachmentError: LocalizedError, Sendable {
    case invalidImage
    case invalidDimensions
    case fileTooLarge
    case unsupportedFormat
    case thumbnailFailed
    case invalidFilename

    var errorDescription: String? {
        switch self {
        case .invalidImage: "图片文件无效"
        case .invalidDimensions: "图片尺寸无效或超过 5000 万像素"
        case .fileTooLarge: "图片超过 20 MB"
        case .unsupportedFormat: "不支持该图片格式"
        case .thumbnailFailed: "无法生成缩略图"
        case .invalidFilename: "附件文件名不安全"
        }
    }
}
