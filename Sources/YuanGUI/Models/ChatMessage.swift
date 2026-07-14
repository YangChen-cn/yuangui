import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum ChatServiceError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case emptyResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置里填写 API Key"
        case .invalidURL: return "API 地址格式不正确"
        case .emptyResponse: return "元圭和 VCC 好像睡着了，请再试一次"
        case .server(let status, let message): return "请求失败（\(status)）：\(message)"
        }
    }
}
