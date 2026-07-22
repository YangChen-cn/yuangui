import Foundation

enum LyricsParser {
    static func parseLRC(_ text: String, source: String = "本地 LRC") -> LyricsDocument {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#)
        var offset: TimeInterval = 0
        var title: String?
        var artist: String?
        var lines: [TimedLyricLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            if rawLine.lowercased().hasPrefix("[offset:"),
               let value = rawLine.split(separator: ":").last?.dropLast(), let milliseconds = Double(value) {
                offset = milliseconds / 1000
            }
            if rawLine.lowercased().hasPrefix("[ti:") { title = metadata(rawLine) }
            if rawLine.lowercased().hasPrefix("[ar:") { artist = metadata(rawLine) }
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = timestamp.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }
            let textStart = matches.last!.range.location + matches.last!.range.length
            let lyric = String(rawLine[rawLine.index(rawLine.startIndex, offsetBy: textStart)...]).trimmingCharacters(in: .whitespaces)
            guard !lyric.isEmpty else { continue }
            for match in matches {
                let minute = number(match, 1, rawLine)
                let second = number(match, 2, rawLine)
                let fractionText = value(match, 3, rawLine)
                let fraction = fractionText.isEmpty ? 0 : Double(fractionText)! / pow(10, Double(fractionText.count))
                lines.append(TimedLyricLine(time: max(0, minute * 60 + second + fraction + offset), text: lyric))
            }
        }
        return LyricsDocument(title: title, artist: artist, lines: lines.sorted { $0.time < $1.time }, source: source)
    }

    private static func metadata(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":"), let end = line.lastIndex(of: "]") else { return nil }
        return String(line[line.index(after: colon)..<end]).trimmingCharacters(in: .whitespaces)
    }
    private static func value(_ match: NSTextCheckingResult, _ index: Int, _ line: String) -> String {
        guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: line) else { return "" }
        return String(line[range])
    }
    private static func number(_ match: NSTextCheckingResult, _ index: Int, _ line: String) -> Double {
        Double(value(match, index, line)) ?? 0
    }
}

actor LyricsService {
    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(session: URLSession = .shared, requestTimeout: TimeInterval = 30) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    func lyrics(for track: MusicTrack) async -> LyricsDocument? {
        if let subtitleURL = track.subtitleURL, let subtitle = try? await loadSubtitle(subtitleURL), !subtitle.lines.isEmpty {
            return subtitle
        }
        return try? await searchLRCLIB(track)
    }

    func search(title: String, artist: String, duration: TimeInterval) async throws -> LyricsDocument? {
        let query = MusicTrack(
            id: "lyrics-search",
            source: .bilibili,
            title: title,
            artist: artist,
            album: nil,
            coverURL: nil,
            duration: duration,
            bilibili: nil,
            subtitleURL: nil
        )
        return try await searchLRCLIB(query)
    }

    private func loadSubtitle(_ url: URL) async throws -> LyricsDocument {
        var request = URLRequest(url: url)
        request.timeoutInterval = min(requestTimeout, 8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LyricsServiceError.invalidResponse
        }
        let subtitle = try JSONDecoder().decode(BilibiliSubtitle.self, from: data)
        let lines = subtitle.body.compactMap { item -> TimedLyricLine? in
            let cleaned = item.content.trimmingCharacters(in: CharacterSet(charactersIn: " ♪♫\n\t"))
            return cleaned.isEmpty ? nil : TimedLyricLine(time: max(0, item.from), text: cleaned)
        }
        return LyricsDocument(title: nil, artist: nil, lines: lines.sorted { $0.time < $1.time }, source: "Bilibili 字幕")
    }

    private func searchLRCLIB(_ track: MusicTrack) async throws -> LyricsDocument? {
        let title = normalizedTitle(track.title)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        var fieldQuery = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            fieldQuery.append(URLQueryItem(name: "artist_name", value: artist))
        }
        let candidates = try await fetchCandidates(queryItems: fieldQuery)
        if let direct = bestDocument(in: candidates, for: track) { return direct }

        // Some LRCLIB records (and some imported Bilibili metadata) have the
        // title and artist fields reversed. Scoring already accepts that shape,
        // but the field-filtered API cannot return it unless we also issue the
        // exact swapped query.
        guard !artist.isEmpty, normalize(title) != normalize(artist) else { return nil }
        let swappedCandidates = try await fetchCandidates(queryItems: [
            URLQueryItem(name: "track_name", value: artist),
            URLQueryItem(name: "artist_name", value: title)
        ])
        return bestDocument(in: swappedCandidates, for: track)
    }

    private func fetchCandidates(queryItems: [URLQueryItem]) async throws -> [LRCLIBResult] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = requestTimeout
        request.setValue("YuanGUI/1.0 (https://github.com/YangChen-cn/yuangui)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LyricsServiceError.invalidResponse }
            guard http.statusCode == 200 else { throw LyricsServiceError.server(statusCode: http.statusCode) }
            do { return try JSONDecoder().decode([LRCLIBResult].self, from: data) }
            catch { throw LyricsServiceError.invalidResponse }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw LyricsServiceError.timedOut }
            throw LyricsServiceError.unavailable
        }
    }

    private func bestDocument(in candidates: [LRCLIBResult], for track: MusicTrack) -> LyricsDocument? {
        guard let best = candidates
            .filter({ $0.syncedLyrics?.isEmpty == false })
            .map({ ($0, score($0, track)) })
            .filter({ $0.1 >= 0.70 })
            .max(by: { $0.1 < $1.1 })?.0,
              let lrc = best.syncedLyrics else { return nil }
        return LyricsParser.parseLRC(lrc, source: "LRCLIB")
    }

    private func score(_ result: LRCLIBResult, _ track: MusicTrack) -> Double {
        let expectedTitle = normalize(normalizedTitle(track.title))
        let candidateTitle = normalize(result.trackName)
        let expectedArtist = normalize(track.artist)
        let candidateArtist = normalize(result.artistName)
        let hasArtist = !expectedArtist.isEmpty
        let directScore = metadataScore(
            candidateTitle: candidateTitle,
            candidateArtist: candidateArtist,
            expectedTitle: expectedTitle,
            expectedArtist: expectedArtist,
            hasArtist: hasArtist
        )
        let swappedScore = hasArtist ? metadataScore(
            candidateTitle: candidateTitle,
            candidateArtist: candidateArtist,
            expectedTitle: expectedArtist,
            expectedArtist: expectedTitle,
            hasArtist: true
        ) : 0
        let durationScore: Double
        if track.duration > 0, abs(result.duration - track.duration) <= 6 {
            durationScore = hasArtist ? 0.13 : 0.22
        } else {
            durationScore = 0
        }
        return max(directScore, swappedScore) + durationScore
    }

    private func metadataScore(
        candidateTitle: String,
        candidateArtist: String,
        expectedTitle: String,
        expectedArtist: String,
        hasArtist: Bool
    ) -> Double {
        let titleExact = candidateTitle == expectedTitle
        let titleContains = !expectedTitle.isEmpty
            && (candidateTitle.contains(expectedTitle) || expectedTitle.contains(candidateTitle))
        let artistExact = hasArtist && candidateArtist == expectedArtist
        let artistContains = hasArtist
            && (candidateArtist.contains(expectedArtist) || expectedArtist.contains(candidateArtist))
        let titleScore: Double = titleExact ? (hasArtist ? 0.58 : 0.78) : (titleContains ? (hasArtist ? 0.45 : 0.62) : 0)
        let artistScore: Double = artistExact ? 0.29 : (artistContains ? 0.22 : 0)
        return titleScore + artistScore
    }

    private func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*[·｜|]\s*P?\d+.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[【\[].*?(MV|官方|歌词).*?[】\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }
    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum LyricsServiceError: LocalizedError, Equatable {
    case timedOut
    case unavailable
    case invalidResponse
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut: return "LRCLIB 响应超时，请稍后重试"
        case .unavailable: return "暂时无法连接 LRCLIB，请检查网络后重试"
        case .invalidResponse: return "LRCLIB 返回了无法识别的数据"
        case .server(let statusCode): return "LRCLIB 服务暂时异常（HTTP \(statusCode)）"
        }
    }
}

private struct BilibiliSubtitle: Decodable { let body: [BilibiliSubtitleItem] }
private struct BilibiliSubtitleItem: Decodable { let from: Double; let content: String }
private struct LRCLIBResult: Decodable {
    let trackName: String; let artistName: String; let duration: Double; let syncedLyrics: String?
}
