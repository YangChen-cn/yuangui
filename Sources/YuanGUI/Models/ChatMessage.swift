import Foundation

struct ChatAttachmentMetadata: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case image, text, pdf }

    let id: UUID
    let name: String
    let kind: Kind
    let byteCount: Int64
    let wasTruncated: Bool

    init(id: UUID = UUID(), name: String, kind: Kind, byteCount: Int64, wasTruncated: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    let attachments: [ChatAttachmentMetadata]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        attachments: [ChatAttachmentMetadata] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String = "新对话", createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct ChatSessionMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int

    init(session: ChatSession) {
        id = session.id
        title = session.title
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        messageCount = session.messages.count
    }

    var placeholder: ChatSession {
        ChatSession(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt, messages: [])
    }
}

struct PreparedChatAttachment: Identifiable {
    enum Payload {
        case imageDataURL(String)
        case extractedText(String)
    }

    let metadata: ChatAttachmentMetadata
    let payload: Payload
    var id: UUID { metadata.id }
}

enum ChatServiceError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case emptyResponse
    case server(status: Int, message: String)
    case unsupportedAttachment(String)
    case attachmentTooLarge(String)
    case unreadableAttachment(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置里填写 API Key"
        case .invalidURL: return "API 地址格式不正确"
        case .emptyResponse: return "元圭和 VCC 好像睡着了，请再试一次"
        case .server(let status, let message): return "请求失败（\(status)）：\(message)"
        case .unsupportedAttachment(let name): return "暂不支持这个文件：\(name)"
        case .attachmentTooLarge(let name): return "文件超过 20 MB：\(name)"
        case .unreadableAttachment(let name): return "无法读取文件内容：\(name)"
        }
    }
}
