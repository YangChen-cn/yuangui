import Foundation

struct BilibiliAccount: Codable, Equatable {
    let mid: Int64
    let name: String
    let avatarURL: URL?
}

struct BilibiliLoginQRCode: Equatable {
    let url: String
    let key: String
}

enum BilibiliLoginPollState: Equatable {
    case waitingForScan
    case waitingForConfirmation
    case expired
    case succeeded
}

enum BilibiliLoginPhase: Equatable {
    case loggedOut
    case requestingQRCode
    case waitingForScan
    case waitingForConfirmation
    case expired
    case loggedIn
    case failed(String)
}

protocol BilibiliSessionPersisting: Sendable {
    func load() throws -> BilibiliStoredSession?
    func save(_ session: BilibiliStoredSession) throws
    func clear() throws
}

struct BilibiliStoredSession: Codable, Equatable, Sendable {
    var refreshToken: String
    var cookies: [BilibiliStoredCookie]
}

struct BilibiliStoredCookie: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let secure: Bool
}

struct BilibiliSessionFileStore: BilibiliSessionPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuanGUI/Music/bilibili-session.json")
    }

    func load() throws -> BilibiliStoredSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(BilibiliStoredSession.self, from: Data(contentsOf: fileURL))
    }

    func save(_ session: BilibiliStoredSession) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(session).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

actor BilibiliAccountService {
    private let session: URLSession
    private let store: BilibiliSessionPersisting
    private let cookieStorage: HTTPCookieStorage
    private var refreshToken = ""
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"

    init(
        session: URLSession = .shared,
        store: BilibiliSessionPersisting = BilibiliSessionFileStore()
    ) {
        self.session = session
        self.store = store
        self.cookieStorage = session.configuration.httpCookieStorage ?? .shared
        if let stored = try? store.load() {
            refreshToken = stored.refreshToken
            Self.restore(stored.cookies, into: cookieStorage)
        }
    }

    func currentAccount() async throws -> BilibiliAccount? {
        let response: AccountNavResponse = try await get(
            URL(string: "https://api.bilibili.com/x/web-interface/nav")!
        )
        guard response.code == 0, let data = response.data, data.isLogin else { return nil }
        return BilibiliAccount(mid: data.mid, name: data.uname, avatarURL: URL(string: data.face))
    }

    func generateQRCode() async throws -> BilibiliLoginQRCode {
        let response: LoginQRCodeResponse = try await get(
            URL(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")!
        )
        guard response.code == 0, let data = response.data else {
            throw BilibiliAccountError.api(response.message)
        }
        return BilibiliLoginQRCode(url: data.url, key: data.qrcodeKey)
    }

    func pollQRCode(key: String) async throws -> BilibiliLoginPollState {
        var components = URLComponents(
            string: "https://passport.bilibili.com/x/passport-login/web/qrcode/poll"
        )!
        components.queryItems = [URLQueryItem(name: "qrcode_key", value: key)]
        let response: LoginPollResponse = try await get(components.url!)
        guard response.code == 0, let data = response.data else {
            throw BilibiliAccountError.api(response.message)
        }
        switch data.code {
        case 0:
            refreshToken = data.refreshToken
            try persistCurrentSession()
            return .succeeded
        case 86038: return .expired
        case 86090: return .waitingForConfirmation
        case 86101: return .waitingForScan
        default: throw BilibiliAccountError.api(data.message)
        }
    }

    func logout() async {
        if let csrf = biliCookies().first(where: { $0.name == "bili_jct" })?.value,
           let url = URL(string: "https://passport.bilibili.com/login/exit/v2") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.httpBody = "biliCSRF=\(Self.formEncode(csrf))&gourl=https%3A%2F%2Fwww.bilibili.com%2F".data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            _ = try? await session.data(for: request)
        }
        clearLocalSession()
    }

    private func persistCurrentSession() throws {
        let cookies = biliCookies().map {
            BilibiliStoredCookie(
                name: $0.name,
                value: $0.value,
                domain: $0.domain,
                path: $0.path,
                expiresAt: $0.expiresDate,
                secure: $0.isSecure
            )
        }
        try store.save(BilibiliStoredSession(refreshToken: refreshToken, cookies: cookies))
    }

    private func clearLocalSession() {
        for cookie in biliCookies() { cookieStorage.deleteCookie(cookie) }
        refreshToken = ""
        try? store.clear()
    }

    private func biliCookies() -> [HTTPCookie] {
        (cookieStorage.cookies ?? []).filter {
            let domain = $0.domain.lowercased()
            return domain == "bilibili.com" || domain.hasSuffix(".bilibili.com")
        }
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BilibiliAccountError.unavailable
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { values, item in
            guard let key = item.key as? String else { return }
            values[key] = String(describing: item.value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            cookieStorage.setCookie(cookie)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func restore(_ cookies: [BilibiliStoredCookie], into storage: HTTPCookieStorage) {
        for cookie in cookies where cookie.expiresAt.map({ $0 > Date() }) ?? true {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path
            ]
            if let expiresAt = cookie.expiresAt { properties[.expires] = expiresAt }
            if cookie.secure { properties[.secure] = "TRUE" }
            if let restored = HTTPCookie(properties: properties) { storage.setCookie(restored) }
        }
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum BilibiliAccountError: LocalizedError {
    case unavailable
    case api(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "无法连接哔哩哔哩登录服务"
        case .api(let message): return "哔哩哔哩登录失败：\(message)"
        }
    }
}

private struct AccountNavResponse: Decodable {
    let code: Int
    let message: String
    let data: AccountNavData?
}

private struct AccountNavData: Decodable {
    let isLogin: Bool
    let mid: Int64
    let uname: String
    let face: String
    enum CodingKeys: String, CodingKey {
        case isLogin = "isLogin"
        case mid, uname, face
    }
}

private struct LoginQRCodeResponse: Decodable {
    let code: Int
    let message: String
    let data: LoginQRCodeData?
}

private struct LoginQRCodeData: Decodable {
    let url: String
    let qrcodeKey: String
    enum CodingKeys: String, CodingKey { case url; case qrcodeKey = "qrcode_key" }
}

private struct LoginPollResponse: Decodable {
    let code: Int
    let message: String
    let data: LoginPollData?
}

private struct LoginPollData: Decodable {
    let url: String
    let refreshToken: String
    let timestamp: Int64
    let code: Int
    let message: String
    enum CodingKeys: String, CodingKey {
        case url, timestamp, code, message
        case refreshToken = "refresh_token"
    }
}
