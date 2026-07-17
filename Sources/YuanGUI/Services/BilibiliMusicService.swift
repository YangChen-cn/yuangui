import AVFoundation
import CryptoKit
import Foundation

enum BilibiliMusicError: LocalizedError {
    case invalidInput
    case unsupportedRedirect
    case api(String)
    case noAudio
    case unreachable

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "请输入有效的 BV 号、Bilibili 视频链接或 b23.tv 短链接"
        case .unsupportedRedirect: return "短链接跳转到了不受支持的网站"
        case .api(let message): return "Bilibili 返回错误：\(message)"
        case .noAudio: return "这个视频没有可公开播放的兼容音频"
        case .unreachable: return "Bilibili 返回了音频地址，但当前所有 CDN 线路都无法连接"
        }
    }
}

struct BilibiliAudioLocation {
    let candidates: [URL]
}

enum BilibiliInputParser {
    static func extractBVID(from value: String) -> String? {
        guard let match = value.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) else { return nil }
        return String(value[match])
    }

    static func isTrustedVideoURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
    }
}

actor BilibiliClient {
    private let session: URLSession
    private var cachedMixinKey: String?
    private var verifiedSubtitleTrackIDs: [String: String] = [:]
    private var guestSessionPrepared = false
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"
    init(session: URLSession = .shared) { self.session = session }

    func resolveTracks(from input: String) async throws -> [MusicTrack] {
        try? await prepareGuestSession()
        let bvid = try await resolveBVID(input)
        let url = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")!
        let response: ViewResponse = try await request(url)
        guard response.code == 0, let data = response.data else { throw BilibiliMusicError.api(response.message) }
        var tracks: [MusicTrack] = []
        for page in data.pages {
            // The top-level subtitle list returned by the view endpoint is not
            // scoped to each page. Always resolve subtitles with the exact CID,
            // otherwise a multi-page video can attach P1's captions to every P.
            let subtitleURL = await subtitleURL(bvid: data.bvid, aid: data.aid, cid: page.cid)
            let title = data.pages.count > 1 ? "\(data.title) · \(page.part)" : data.title
            tracks.append(MusicTrack(
                id: "bili:\(data.bvid):\(page.cid)",
                source: .bilibili,
                title: title,
                artist: data.owner.name,
                album: data.pages.count > 1 ? "P\(page.page) · \(page.part)" : nil,
                coverURL: Self.normalizedURL(page.firstFrame ?? data.pic),
                duration: TimeInterval(page.duration),
                bilibili: BilibiliTrackReference(bvid: data.bvid, aid: data.aid, cid: page.cid, page: page.page),
                subtitleURL: subtitleURL
            ))
        }
        return tracks
    }

    func audioLocation(for track: MusicTrack) async throws -> BilibiliAudioLocation {
        try? await prepareGuestSession()
        guard let reference = track.bilibili else { throw BilibiliMusicError.invalidInput }
        // AVFoundation cannot reliably open Bilibili's standalone fragmented-MP4
        // audio segments. Ask for the HTML5 progressive stream first, matching
        // BBPlayer's Apple-platform fallback, and retain DASH as a last resort.
        let progressiveParams = [
            "bvid": reference.bvid,
            "cid": String(reference.cid),
            "qn": "64",
            "fnval": "1",
            "fnver": "0",
            "fourk": "0",
            "platform": "html5"
        ]
        if let response = try? await successfulPlayResponse(params: progressiveParams),
           let durl = response.data?.durl?.first {
            let progressiveURLs = ([durl.url] + durl.backupURL).compactMap(Self.playbackURL)
            if let location = await reachableLocation(from: progressiveURLs) { return location }
        }

        let params = [
            "bvid": reference.bvid,
            "cid": String(reference.cid),
            "qn": "64",
            "fnval": "16",
            "fnver": "0",
            "fourk": "0",
            "try_look": "1",
            "gaia_source": "view-card"
        ]
        let resolved = try await successfulPlayResponse(params: params)
        guard let audio = resolved.data?.dash?.audio
            .max(by: { $0.bandwidth < $1.bandwidth }) else {
            throw BilibiliMusicError.noAudio
        }
        let allURLs = ([audio.baseURL] + audio.backupURL).compactMap(Self.playbackURL)
        guard let location = await reachableLocation(from: allURLs) else {
            throw BilibiliMusicError.unreachable
        }
        return location
    }

    func subtitleURL(for track: MusicTrack) async -> URL? {
        guard let reference = track.bilibili else { return nil }
        try? await prepareGuestSession()
        return await subtitleURL(bvid: reference.bvid, aid: reference.aid, cid: reference.cid)
    }

    private func successfulPlayResponse(params: [String: String]) async throws -> PlayResponse {
        let response = try await playResponse(params: params, signed: false)
        if response.code == 0 { return response }
        if let fallback = try? await playResponse(params: params, signed: true), fallback.code == 0 {
            return fallback
        }
        throw BilibiliMusicError.api(response.message)
    }

    private func subtitleURL(bvid: String, aid: Int, cid: Int) async -> URL? {
        let params = ["bvid": bvid, "cid": String(cid)]
        let trackKey = "\(bvid.lowercased()):\(cid)"
        let previouslyVerifiedID = verifiedSubtitleTrackIDs[trackKey]
        var sightings: [String: (count: Int, url: URL)] = [:]

        // Bilibili's player endpoint can intermittently keep the requested
        // bvid/cid at the top level while returning another video's subtitle
        // item. Retry and require evidence tied to this CID or a repeated,
        // stable subtitle identity before accepting it.
        for attempt in 0..<10 {
            let signed = attempt >= 7
            guard let response = try? await playerInfoResponse(params: params, signed: signed) else { continue }
            let candidates = validatedSubtitleCandidates(in: response, bvid: bvid, cid: cid)
            guard !candidates.isEmpty else { continue }
            let hasHumanSubtitle = candidates.contains { !$0.item.isAIGenerated }

            for candidate in candidates where !hasHumanSubtitle || !candidate.item.isAIGenerated {
                let identity = candidate.item.stableIdentity(url: candidate.url)
                if identity == previouslyVerifiedID {
                    verifiedSubtitleTrackIDs[trackKey] = identity
                    return candidate.url
                }
                let subtitlePath = candidate.url.path
                if candidate.item.isAIGenerated {
                    guard subtitlePath.localizedCaseInsensitiveContains(String(aid)),
                          subtitlePath.localizedCaseInsensitiveContains(String(cid)) else { continue }
                    verifiedSubtitleTrackIDs[trackKey] = identity
                    return candidate.url
                }
                let previous = sightings[identity]
                let count = (previous?.count ?? 0) + 1
                sightings[identity] = (count, candidate.url)
                if count >= 2 {
                    verifiedSubtitleTrackIDs[trackKey] = identity
                    return candidate.url
                }
            }
        }
        return nil
    }

    private func validatedSubtitleCandidates(
        in response: PlayerInfoResponse,
        bvid: String,
        cid: Int
    ) -> [(item: PlayerSubtitleItem, url: URL)] {
        guard response.code == 0,
              let data = response.data,
              data.cid == cid,
              data.bvid.caseInsensitiveCompare(bvid) == .orderedSame else { return [] }
        return (data.subtitle?.subtitles ?? [])
            .compactMap { item in Self.normalizedURL(item.bestURL).map { (item, $0) } }
            .sorted { lhs, rhs in
                if lhs.item.isAIGenerated != rhs.item.isAIGenerated { return !lhs.item.isAIGenerated }
                return lhs.item.languageRank < rhs.item.languageRank
            }
    }

    private func playerInfoResponse(params: [String: String], signed: Bool) async throws -> PlayerInfoResponse {
        var components = URLComponents(string: signed
            ? "https://api.bilibili.com/x/player/wbi/v2"
            : "https://api.bilibili.com/x/player/v2")!
        let values = signed ? try await signedParameters(params) : params
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return try await request(components.url!)
    }

    private func reachableLocation(from urls: [URL]) async -> BilibiliAudioLocation? {
        let candidates = Array(Set(urls)).sorted { lhs, rhs in
            let lhsMCDN = lhs.host?.contains("mcdn") == true
            let rhsMCDN = rhs.host?.contains("mcdn") == true
            if lhsMCDN != rhsMCDN { return !lhsMCDN }
            return lhs.absoluteString < rhs.absoluteString
        }
        guard !candidates.isEmpty,
              let reachable = await firstReachableURL(in: candidates) else { return nil }
        return BilibiliAudioLocation(candidates: [reachable] + candidates.filter { $0 != reachable })
    }

    func playbackHeaders() -> [String: String] {
        let cookies = cookieStorage.cookies(for: URL(string: "https://www.bilibili.com/")!) ?? []
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
        var headers = [
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com",
            "User-Agent": Self.userAgent
        ]
        if let cookieHeader, !cookieHeader.isEmpty { headers["Cookie"] = cookieHeader }
        return headers
    }

    private var cookieStorage: HTTPCookieStorage {
        session.configuration.httpCookieStorage ?? .shared
    }

    private func prepareGuestSession() async throws {
        guard !guestSessionPrepared else { return }
        let siteURL = URL(string: "https://www.bilibili.com/")!
        let existing = cookieStorage.cookies(for: siteURL) ?? []
        let existingNames = Set(existing.map(\.name))

        if !existingNames.contains("buvid3") || !existingNames.contains("buvid4") {
            let response: FingerprintResponse = try await request(
                URL(string: "https://api.bilibili.com/x/frontend/finger/spi_v2")!
            )
            guard response.code == 0, let fingerprint = response.data else {
                throw BilibiliMusicError.api(response.message)
            }
            setCookie(name: "buvid3", value: fingerprint.buvid3, expiresAfter: 30 * 24 * 60 * 60)
            setCookie(name: "buvid4", value: fingerprint.buvid4, expiresAfter: 30 * 24 * 60 * 60)
        }

        if !existingNames.contains("bili_ticket") {
            let timestamp = Int(Date().timeIntervalSince1970)
            let key = SymmetricKey(data: Data("XgwSnGZ1p".utf8))
            let signature = HMAC<SHA256>.authenticationCode(
                for: Data("ts\(timestamp)".utf8),
                using: key
            ).map { String(format: "%02x", $0) }.joined()
            var components = URLComponents(
                string: "https://api.bilibili.com/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket"
            )!
            components.queryItems = [
                URLQueryItem(name: "key_id", value: "ec02"),
                URLQueryItem(name: "hexsign", value: signature),
                URLQueryItem(name: "context[ts]", value: String(timestamp)),
                URLQueryItem(name: "csrf", value: "")
            ]
            var ticketRequest = URLRequest(url: components.url!)
            ticketRequest.httpMethod = "POST"
            ticketRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: ticketRequest)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw BilibiliMusicError.api("匿名游客凭据请求失败")
            }
            let ticket = try JSONDecoder().decode(TicketResponse.self, from: data)
            guard ticket.code == 0, let value = ticket.data?.ticket, !value.isEmpty else {
                throw BilibiliMusicError.api(ticket.message)
            }
            setCookie(name: "bili_ticket", value: value, expiresAfter: 3 * 24 * 60 * 60)
            setCookie(name: "bili_ticket_expires", value: String(timestamp + 3 * 24 * 60 * 60), expiresAfter: 3 * 24 * 60 * 60)
        }
        guestSessionPrepared = true
    }

    private func setCookie(name: String, value: String, expiresAfter seconds: TimeInterval) {
        guard let cookie = HTTPCookie(properties: [
            .domain: ".bilibili.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(seconds)
        ]) else { return }
        cookieStorage.setCookie(cookie)
    }

    private func firstReachableURL(in candidates: [URL]) async -> URL? {
        let headers = playbackHeaders()
        for url in candidates.prefix(4) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else { continue }
            return url
        }
        return nil
    }

    private func resolveBVID(_ raw: String) async throws -> String {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bvid = BilibiliInputParser.extractBVID(from: input) { return bvid }
        guard let url = URL(string: input), url.scheme?.lowercased() == "https" else { throw BilibiliMusicError.invalidInput }
        if url.host?.lowercased() == "b23.tv" {
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (_, response) = try await session.data(for: request)
            guard let finalURL = response.url, BilibiliInputParser.isTrustedVideoURL(finalURL),
                  let bvid = BilibiliInputParser.extractBVID(from: finalURL.absoluteString) else {
                throw BilibiliMusicError.unsupportedRedirect
            }
            return bvid
        }
        guard BilibiliInputParser.isTrustedVideoURL(url), let bvid = BilibiliInputParser.extractBVID(from: url.absoluteString) else {
            throw BilibiliMusicError.invalidInput
        }
        return bvid
    }

    private func signedParameters(_ params: [String: String]) async throws -> [String: String] {
        let mixin = try await mixinKey()
        var values = params
        values["wts"] = String(Int(Date().timeIntervalSince1970))
        let filtered = values.mapValues { $0.filter { !"!'()*".contains($0) } }
        let query = filtered.keys.sorted().map { "\(Self.escape($0))=\(Self.escape(filtered[$0]!))" }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + mixin).utf8)).map { String(format: "%02x", $0) }.joined()
        values["w_rid"] = digest
        return values
    }

    private func playResponse(params: [String: String], signed: Bool) async throws -> PlayResponse {
        var components = URLComponents(string: signed
            ? "https://api.bilibili.com/x/player/wbi/playurl"
            : "https://api.bilibili.com/x/player/playurl")!
        let values = signed ? try await signedParameters(params) : params
        components.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await request(components.url!)
    }

    private func mixinKey() async throws -> String {
        if let cachedMixinKey { return cachedMixinKey }
        let response: NavResponse = try await request(URL(string: "https://api.bilibili.com/x/web-interface/nav")!)
        guard response.code == 0, let image = response.data?.wbiImg,
              let first = URL(string: image.imgURL)?.deletingPathExtension().lastPathComponent,
              let second = URL(string: image.subURL)?.deletingPathExtension().lastPathComponent else {
            throw BilibiliMusicError.api(response.message)
        }
        let source = Array(first + second)
        let table = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]
        let key = String(table.compactMap { $0 < source.count ? source[$0] : nil }.prefix(32))
        cachedMixinKey = key
        return key
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BilibiliMusicError.api("网络请求失败")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func normalizedURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              var components = URLComponents(string: value.hasPrefix("//") ? "https:\(value)" : value) else {
            return nil
        }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        return components.url
    }

    private static func playbackURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value.hasPrefix("//") ? "https:\(value)" : value) else {
            return nil
        }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https" else { return nil }
        return components.url
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "!$&'()*+,/:;=?@[]")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct ViewResponse: Decodable {
    let code: Int; let message: String; let data: ViewData?
}
private struct FingerprintResponse: Decodable {
    let code: Int; let message: String; let data: FingerprintData?
}
private struct FingerprintData: Decodable {
    let buvid3: String; let buvid4: String
    enum CodingKeys: String, CodingKey { case buvid3 = "b_3"; case buvid4 = "b_4" }
}
private struct TicketResponse: Decodable {
    let code: Int; let message: String; let data: TicketData?
}
private struct TicketData: Decodable { let ticket: String }
private struct ViewData: Decodable {
    let bvid: String; let aid: Int; let title: String; let pic: String; let owner: ViewOwner; let pages: [ViewPage]
}
private struct ViewOwner: Decodable { let name: String }
private struct ViewPage: Decodable {
    let cid: Int; let page: Int; let part: String; let duration: Int; let firstFrame: String?
    enum CodingKeys: String, CodingKey { case cid, page, part, duration; case firstFrame = "first_frame" }
}
private struct PlayerInfoResponse: Decodable {
    let code: Int; let message: String; let data: PlayerInfoData?
}
private struct PlayerInfoData: Decodable {
    let bvid: String
    let cid: Int
    let subtitle: PlayerInfoSubtitle?
}
private struct PlayerInfoSubtitle: Decodable { let subtitles: [PlayerSubtitleItem] }
private struct PlayerSubtitleItem: Decodable {
    let id: Int64?
    let idString: String?
    let language: String?
    let subtitleURL: String?
    let subtitleURLV2: String?
    var bestURL: String { subtitleURL ?? subtitleURLV2 ?? "" }
    var isAIGenerated: Bool { language?.lowercased().hasPrefix("ai-") == true }
    var languageRank: Int {
        let value = language?.lowercased() ?? ""
        if value.contains("zh") { return 0 }
        if value.contains("en") { return 1 }
        return 2
    }
    func stableIdentity(url: URL) -> String {
        if let idString, !idString.isEmpty { return "id:\(idString)" }
        if let id { return "id:\(id)" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return "url:\(components?.url?.absoluteString ?? url.absoluteString)"
    }
    enum CodingKeys: String, CodingKey {
        case id
        case idString = "id_str"
        case language = "lan"
        case subtitleURL = "subtitle_url"
        case subtitleURLV2 = "subtitle_url_v2"
    }
}
private struct NavResponse: Decodable { let code: Int; let message: String; let data: NavData? }
private struct NavData: Decodable {
    let wbiImg: WBIImage
    enum CodingKeys: String, CodingKey { case wbiImg = "wbi_img" }
}
private struct WBIImage: Decodable {
    let imgURL: String; let subURL: String
    enum CodingKeys: String, CodingKey { case imgURL = "img_url"; case subURL = "sub_url" }
}
private struct PlayResponse: Decodable { let code: Int; let message: String; let data: PlayData? }
private struct PlayData: Decodable { let dash: PlayDash?; let durl: [PlayDURL]? }
private struct PlayDash: Decodable { let audio: [PlayAudio] }
private struct PlayDURL: Decodable {
    let url: String
    let backupURL: [String]
    enum CodingKeys: String, CodingKey { case url; case backupURL = "backup_url"; case backupURLCamel = "backupUrl" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        backupURL = try values.decodeIfPresent([String].self, forKey: .backupURL)
            ?? values.decodeIfPresent([String].self, forKey: .backupURLCamel) ?? []
    }
}
private struct PlayAudio: Decodable {
    let id: Int; let baseURL: String; let backupURL: [String]; let bandwidth: Int
    enum CodingKeys: String, CodingKey { case id; case baseURL = "baseUrl"; case baseURLSnake = "base_url"; case backupURL = "backupUrl"; case backupURLSnake = "backup_url"; case bandwidth }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? values.decode(String.self, forKey: .baseURLSnake)
        backupURL = try values.decodeIfPresent([String].self, forKey: .backupURL)
            ?? values.decodeIfPresent([String].self, forKey: .backupURLSnake) ?? []
        bandwidth = try values.decode(Int.self, forKey: .bandwidth)
    }
}
