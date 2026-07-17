import Foundation

enum BilibiliFavoriteFolderKind: String, CaseIterable, Sendable {
    case created
    case collected

    var title: String {
        switch self {
        case .created: return "我的收藏夹"
        case .collected: return "收藏的视频收藏夹"
        }
    }
}

struct BilibiliFavoriteFolder: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String
    let coverURL: URL?
    let mediaCount: Int
    let kind: BilibiliFavoriteFolderKind
    let ownerName: String?
}

enum BilibiliFavoritesError: LocalizedError {
    case unavailable
    case notLoggedIn
    case api(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "无法连接哔哩哔哩收藏夹服务"
        case .notLoggedIn: return "登录状态已失效，请重新登录哔哩哔哩"
        case .api(let message): return "读取哔哩哔哩收藏夹失败：\(message)"
        }
    }
}

actor BilibiliFavoritesService {
    private let session: URLSession
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func folders(for accountMID: Int64) async throws -> [BilibiliFavoriteFolder] {
        let created = try await folderPages(
            path: "/x/v3/fav/folder/created/list",
            accountMID: accountMID,
            kind: .created
        )
        let collected = try await folderPages(
            path: "/x/v3/fav/folder/collected/list",
            accountMID: accountMID,
            kind: .collected
        )
        var seen = Set<Int64>()
        return (created + collected).filter { seen.insert($0.id).inserted }
    }

    func videoBVIDs(in folder: BilibiliFavoriteFolder) async throws -> [String] {
        var components = URLComponents(string: "https://api.bilibili.com/x/v3/fav/resource/ids")!
        components.queryItems = [
            URLQueryItem(name: "media_id", value: String(folder.id)),
            URLQueryItem(name: "platform", value: "web")
        ]
        let response: FavoriteResourceIDsResponse = try await request(components.url!)
        try validate(code: response.code, message: response.message)
        var seen = Set<String>()
        return (response.data ?? []).compactMap { item in
            guard item.type == 2 else { return nil }
            let bvid = item.bvid?.isEmpty == false ? item.bvid : item.bvID
            guard let bvid, !bvid.isEmpty, seen.insert(bvid).inserted else { return nil }
            return bvid
        }
    }

    private func folderPages(
        path: String,
        accountMID: Int64,
        kind: BilibiliFavoriteFolderKind
    ) async throws -> [BilibiliFavoriteFolder] {
        var folders: [BilibiliFavoriteFolder] = []
        for page in 1...20 {
            var components = URLComponents(string: "https://api.bilibili.com\(path)")!
            components.queryItems = [
                URLQueryItem(name: "up_mid", value: String(accountMID)),
                URLQueryItem(name: "ps", value: "50"),
                URLQueryItem(name: "pn", value: String(page)),
                URLQueryItem(name: "platform", value: "web")
            ]
            let response: FavoriteFolderListResponse = try await request(components.url!)
            try validate(code: response.code, message: response.message)
            guard let data = response.data else { break }
            let pageFolders = (data.list ?? []).compactMap { item -> BilibiliFavoriteFolder? in
                guard item.state == 0 else { return nil }
                // Bilibili currently returns type 0 for folders created by the
                // signed-in user. Type 11 is used by collected video folders,
                // while type 21 represents a video collection that this importer
                // cannot resolve as a regular favorite folder.
                if kind == .collected, item.type == 21 { return nil }
                return BilibiliFavoriteFolder(
                    id: item.id,
                    title: item.title,
                    coverURL: Self.normalizedURL(item.cover),
                    mediaCount: item.mediaCount,
                    kind: kind,
                    ownerName: item.upper?.name
                )
            }
            folders.append(contentsOf: pageFolders)
            if !data.hasMore { break }
        }
        return folders
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BilibiliFavoritesError.unavailable
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validate(code: Int, message: String) throws {
        if code == -101 { throw BilibiliFavoritesError.notLoggedIn }
        guard code == 0 else { throw BilibiliFavoritesError.api(message) }
    }

    private static func normalizedURL(_ value: String?) -> URL? {
        guard var value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("http://") { value = "https://" + value.dropFirst("http://".count) }
        return URL(string: value)
    }
}

private struct FavoriteFolderListResponse: Decodable {
    let code: Int
    let message: String
    let data: FavoriteFolderListData?
}

private struct FavoriteFolderListData: Decodable {
    let list: [FavoriteFolderListItem]?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case list
        case hasMore = "has_more"
    }
}

private struct FavoriteFolderListItem: Decodable {
    let id: Int64
    let title: String
    let cover: String?
    let state: Int
    let type: Int?
    let mediaCount: Int
    let upper: FavoriteFolderUpper?

    enum CodingKeys: String, CodingKey {
        case id, title, cover, state, type, upper
        case mediaCount = "media_count"
    }
}

private struct FavoriteFolderUpper: Decodable {
    let name: String
}

private struct FavoriteResourceIDsResponse: Decodable {
    let code: Int
    let message: String
    let data: [FavoriteResourceID]?
}

private struct FavoriteResourceID: Decodable {
    let type: Int
    let bvid: String?
    let bvID: String?

    enum CodingKeys: String, CodingKey {
        case type, bvid
        case bvID = "bv_id"
    }
}
