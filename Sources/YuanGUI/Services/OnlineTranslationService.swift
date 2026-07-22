import Foundation

struct AITranslationConfiguration: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String

    var isUsable: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol OnlineTranslationServicing {
    func translate(
        _ text: String,
        target: QuickToolLanguage,
        configuration: AITranslationConfiguration
    ) async throws -> String
}

struct OnlineTranslationService: OnlineTranslationServicing {
    var session: URLSession = .shared

    func translate(
        _ text: String,
        target: QuickToolLanguage,
        configuration: AITranslationConfiguration
    ) async throws -> String {
        guard configuration.isUsable else { throw OnlineTranslationError.notConfigured }
        guard let endpoint = AIChatService.chatEndpoint(from: configuration.baseURL) else {
            throw OnlineTranslationError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "api-key")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Request(
            model: configuration.model,
            messages: [
                .init(role: "system", content: "Translate the user's text into \(target.title). Return only the translation. Preserve paragraphs, punctuation, names, numbers, and formatting. Do not explain."),
                .init(role: "user", content: text)
            ],
            maxCompletionTokens: 2048,
            temperature: 0
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineTranslationError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            throw OnlineTranslationError.server(http.statusCode, String(detail.prefix(200)))
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let result = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else {
            throw OnlineTranslationError.emptyResponse
        }
        return result
    }
}

enum OnlineTranslationError: LocalizedError {
    case notConfigured
    case invalidURL
    case emptyResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "在线翻译需要先在 AI 设置中填写服务地址、模型和 API Key。"
        case .invalidURL: "在线翻译服务地址无效。"
        case .emptyResponse: "在线翻译没有返回译文。"
        case let .server(status, message): "在线翻译失败（HTTP \(status)）：\(message)"
        }
    }
}

private struct Request: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let maxCompletionTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxCompletionTokens = "max_completion_tokens"
    }
}

private struct Response: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}
