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

protocol OnlineTranslationServicing: Sendable {
    func translate(
        _ text: String,
        target: QuickToolLanguage,
        configuration: AITranslationConfiguration
    ) async throws -> String
    func translateSegments(
        _ segments: [TranslationSegment],
        target: QuickToolLanguage,
        configuration: AITranslationConfiguration
    ) async throws -> [TranslationSegmentResult]
}

extension OnlineTranslationServicing {
    func translateSegments(
        _ segments: [TranslationSegment],
        target: QuickToolLanguage,
        configuration: AITranslationConfiguration
    ) async throws -> [TranslationSegmentResult] {
        let translated = try await translate(
            ScreenshotTranslationLineAligner.combinedText(for: segments.map(\.sourceText)),
            target: target,
            configuration: configuration
        )
        let aligned = ScreenshotTranslationLineAligner.align(translated, to: segments.map(\.sourceText))
        return zip(segments, aligned).map { segment, text in
            TranslationSegmentResult(id: segment.id, sourceText: segment.sourceText, translatedText: text)
        }
    }
}

struct OnlineTranslationService: OnlineTranslationServicing, Sendable {
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

    func translateSegments(
        _ segments: [TranslationSegment],
        target: QuickToolLanguage,
        configuration: AITranslationConfiguration
    ) async throws -> [TranslationSegmentResult] {
        guard !segments.isEmpty else { return [] }
        let input = SegmentInput(segments: segments.map { .init(id: $0.id, text: $0.sourceText) })
        let content = try await requestTranslation(
            systemPrompt: "Translate every JSON segment into \(target.title). Return valid JSON only, using exactly this shape: {\"segments\":[{\"id\":\"same id\",\"text\":\"translation\"}]}. Keep every id unchanged. Preserve names, numbers, URLs, email addresses and punctuation. Do not add explanations.",
            userContent: String(data: try JSONEncoder().encode(input), encoding: .utf8) ?? "",
            configuration: configuration,
            maximumTokens: min(8_192, max(2_048, segments.reduce(0) { $0 + $1.sourceText.count } * 3))
        )
        if let decoded = Self.decodeSegmentOutput(content, sourceSegments: segments) {
            return decoded
        }
        let aligned = ScreenshotTranslationLineAligner.align(Self.plainText(from: content), to: segments.map(\.sourceText))
        return zip(segments, aligned).map { segment, text in
            TranslationSegmentResult(id: segment.id, sourceText: segment.sourceText, translatedText: text)
        }
    }

    private func requestTranslation(
        systemPrompt: String,
        userContent: String,
        configuration: AITranslationConfiguration,
        maximumTokens: Int
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
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userContent)
            ],
            maxCompletionTokens: maximumTokens,
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

    private static func decodeSegmentOutput(
        _ content: String,
        sourceSegments: [TranslationSegment]
    ) -> [TranslationSegmentResult]? {
        let json = plainText(from: content)
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SegmentOutput.self, from: data) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: decoded.segments.map { ($0.id, $0.text) })
        guard values.count == sourceSegments.count,
              sourceSegments.allSatisfy({ values[$0.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
            return nil
        }
        return sourceSegments.map { segment in
            TranslationSegmentResult(
                id: segment.id,
                sourceText: segment.sourceText,
                translatedText: values[segment.id]!.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func plainText(from content: String) -> String {
        var value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SegmentInput: Encodable {
    struct Item: Encodable { let id: String; let text: String }
    let segments: [Item]
}

private struct SegmentOutput: Decodable {
    struct Item: Decodable { let id: String; let text: String }
    let segments: [Item]
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
