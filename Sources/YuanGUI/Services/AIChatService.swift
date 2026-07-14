import Foundation

protocol AIChatServicing {
    func reply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String
}

struct AIChatConfiguration {
    let baseURL: String
    let model: String
    let apiKey: String
    let systemPrompt: String
}

struct AIChatService: AIChatServicing {
    var session: URLSession = .shared

    func reply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment] = [],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ChatServiceError.missingAPIKey }
        guard let endpoint = Self.chatEndpoint(from: configuration.baseURL) else {
            throw ChatServiceError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let modeContext = "当前桌宠角色：\(petMode.title)。请让回复口吻与当前角色相符。"
        let context = Array(messages.suffix(12))
        let requestMessages = context.enumerated().map { index, message in
            RequestPayload.Message(
                role: message.role.rawValue,
                content: index == context.count - 1 && message.role == .user && !attachments.isEmpty
                    ? .parts(Self.contentParts(text: message.content, attachments: attachments))
                    : .text(message.content)
            )
        }
        let payload = RequestPayload(
            model: configuration.model,
            messages: [
                .init(role: "system", content: .text(configuration.systemPrompt + "\n\n" + modeContext))
            ] + requestMessages,
            maxCompletionTokens: 768,
            temperature: 0.9,
            topP: 0.95,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatServiceError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            throw ChatServiceError.server(status: http.statusCode, message: String(error.prefix(240)))
        }
        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        guard let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw ChatServiceError.emptyResponse
        }
        return content
    }

    static func chatEndpoint(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        return components.url
    }

    private static func contentParts(text: String, attachments: [PreparedChatAttachment]) -> [RequestPayload.ContentPart] {
        var parts: [RequestPayload.ContentPart] = attachments.compactMap { attachment in
            switch attachment.payload {
            case .imageDataURL(let url):
                return .imageURL(url)
            case .extractedText:
                return nil
            }
        }
        var textBlocks = [text]
        for attachment in attachments {
            if case .extractedText(let content) = attachment.payload {
                textBlocks.append("附件《\(attachment.metadata.name)》内容：\n\(content)")
            }
        }
        parts.append(.text(textBlocks.joined(separator: "\n\n")))
        return parts
    }
}

private struct RequestPayload: Encodable {
    struct Message: Encodable {
        let role: String
        let content: Content
    }

    enum Content: Encodable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    enum ContentPart: Encodable {
        case text(String)
        case imageURL(String)

        enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }
        enum ImageKeys: String, CodingKey { case url }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                var image = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
                try image.encode(url, forKey: .url)
            }
        }
    }
    let model: String
    let messages: [Message]
    let maxCompletionTokens: Int
    let temperature: Double
    let topP: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxCompletionTokens = "max_completion_tokens"
        case topP = "top_p"
    }
}

private struct ResponsePayload: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct ErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}
