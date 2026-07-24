import Foundation

/// 日记附件元数据
struct DiaryAttachment: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    /// 存储文件名（UUID 命名，防冲突）
    var filename: String
    /// 用户原始文件名
    var originalFilename: String
    /// MIME 类型，如 "image/jpeg"
    var mimeType: String
    var createdAt: Date

    /// 缩略图文件名
    var thumbnailFilename: String {
        (filename as NSString).deletingPathExtension + ".thumb.jpg"
    }

    init(
        id: UUID = UUID(),
        filename: String,
        originalFilename: String,
        mimeType: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.createdAt = createdAt
    }
}
