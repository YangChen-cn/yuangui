import Foundation

protocol AIModelListing {
    func models(baseURL: String, apiKey: String) async throws -> [String]
}

struct AIModelService: AIModelListing {
    var session: URLSession = .shared

    func models(baseURL: String, apiKey: String) async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIModelDiscoveryError.missingAPIKey }
        guard let endpoint = Self.modelsEndpoint(from: baseURL) else {
            throw AIModelDiscoveryError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIModelDiscoveryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ModelErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            throw AIModelDiscoveryError.server(status: http.statusCode, message: String(message.prefix(240)))
        }

        guard let envelope = try? JSONDecoder().decode(ModelListEnvelope.self, from: data) else {
            throw AIModelDiscoveryError.invalidResponse
        }
        let identifiers = (envelope.data ?? envelope.models ?? [])
            .map(\.id)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let models = Array(Set(identifiers)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !models.isEmpty else { throw AIModelDiscoveryError.noModels }
        return models
    }

    static func modelsEndpoint(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else { return nil }

        var segments = components.path.split(separator: "/").map(String.init)
        if segments.suffix(2) == ["chat", "completions"] {
            segments.removeLast(2)
        } else if segments.last == "models" {
            components.path = "/" + segments.joined(separator: "/")
            return components.url
        }
        segments.append("models")
        components.path = "/" + segments.joined(separator: "/")
        return components.url
    }
}

enum AIModelDiscoveryError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case noModels
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先填写 API Key"
        case .invalidURL: return "API 地址格式不正确"
        case .invalidResponse: return "服务没有返回有效响应"
        case .noModels: return "连接成功，但没有读取到可用模型"
        case .server(let status, let message): return "连接失败（\(status)）：\(message)"
        }
    }
}

private struct ModelListEnvelope: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]?
    let models: [Model]?
}

private struct ModelErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}
