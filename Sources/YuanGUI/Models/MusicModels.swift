import Foundation

enum MusicSource: String, Codable, CaseIterable, Identifiable {
    case appleMusic
    case bilibili

    var id: String { rawValue }
    var title: String { self == .appleMusic ? "Apple Music" : "哔哩哔哩" }
    var systemImage: String { self == .appleMusic ? "music.note" : "play.tv.fill" }
}

enum MusicPlaybackState: Equatable {
    case stopped
    case loading
    case playing
    case paused
    case failed(String)

    var isPlaying: Bool { self == .playing }
}

enum MusicPlayMode: String, Codable, CaseIterable, Identifiable {
    case sequential
    case repeatOne
    case repeatAll

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .repeatAll: return "列表循环"
        }
    }
    var systemImage: String {
        switch self {
        case .sequential: return "arrow.right"
        case .repeatOne: return "repeat.1"
        case .repeatAll: return "repeat"
        }
    }
}

enum LyricsFontStyle: String, CaseIterable, Identifiable {
    case rounded
    case system
    case serif
    case monospaced

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rounded: return "圆体"
        case .system: return "系统字体"
        case .serif: return "衬线体"
        case .monospaced: return "等宽体"
        }
    }
}

struct BilibiliTrackReference: Codable, Hashable {
    let bvid: String
    let aid: Int
    let cid: Int
    let page: Int
}

struct MusicTrack: Codable, Identifiable, Hashable {
    let id: String
    let source: MusicSource
    var title: String
    var artist: String
    var album: String?
    var coverURL: URL?
    var duration: TimeInterval
    var bilibili: BilibiliTrackReference?
    var subtitleURL: URL?

    var lyricsCacheKey: String {
        switch source {
        case .bilibili:
            return id
        case .appleMusic:
            return "lyrics:apple:\(Self.normalizedLyricsMetadata(title))\u{1F}\(Self.normalizedLyricsMetadata(artist))"
        }
    }

    func matchesLegacyLyricsCacheKey(_ key: String) -> Bool {
        guard source == .appleMusic,
              let separator = id.lastIndex(of: "|") else { return false }
        let metadataPrefix = String(id[...separator])
        guard key.hasPrefix(metadataPrefix) else { return false }
        return Int(key.dropFirst(metadataPrefix.count)) != nil
    }

    private static func normalizedLyricsMetadata(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func appleMusic(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval,
        coverURL: URL? = nil
    ) -> MusicTrack {
        MusicTrack(
            id: "apple:\(title)|\(artist)|\(Int(duration))",
            source: .appleMusic,
            title: title,
            artist: artist,
            album: album,
            coverURL: coverURL,
            duration: duration,
            bilibili: nil,
            subtitleURL: nil
        )
    }
}

struct TimedLyricLine: Codable, Hashable, Identifiable {
    let time: TimeInterval
    let text: String
    var id: String { "\(time)-\(text)" }
}

struct LyricsDocument: Codable, Equatable {
    var title: String?
    var artist: String?
    var lines: [TimedLyricLine]
    var source: String

    func line(at position: TimeInterval) -> TimedLyricLine? {
        lines.last(where: { $0.time <= position })
    }

    func nextLine(after position: TimeInterval) -> TimedLyricLine? {
        lines.first(where: { $0.time > position })
    }
}

struct SavedMusicPlaylist: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [String]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, trackIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
    }
}

struct MusicLibrarySnapshot: Codable {
    var playlist: [MusicTrack] = []
    var playMode: MusicPlayMode = .sequential
    var currentTrackID: String?
    var lastPosition: TimeInterval = 0
    var favoriteTrackIDs: Set<String> = []
    var savedPlaylists: [SavedMusicPlaylist] = []
    var lyricOffsets: [String: TimeInterval] = [:]
    var lyricsByTrackID: [String: LyricsDocument] = [:]

    init(
        playlist: [MusicTrack] = [],
        playMode: MusicPlayMode = .sequential,
        currentTrackID: String? = nil,
        lastPosition: TimeInterval = 0,
        favoriteTrackIDs: Set<String> = [],
        savedPlaylists: [SavedMusicPlaylist] = [],
        lyricOffsets: [String: TimeInterval] = [:],
        lyricsByTrackID: [String: LyricsDocument] = [:]
    ) {
        self.playlist = playlist
        self.playMode = playMode
        self.currentTrackID = currentTrackID
        self.lastPosition = lastPosition
        self.favoriteTrackIDs = favoriteTrackIDs
        self.savedPlaylists = savedPlaylists
        self.lyricOffsets = lyricOffsets
        self.lyricsByTrackID = lyricsByTrackID
    }

    private enum CodingKeys: String, CodingKey {
        case playlist, playMode, currentTrackID, lastPosition, favoriteTrackIDs, savedPlaylists, lyricOffsets, lyricsByTrackID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playlist = try values.decodeIfPresent([MusicTrack].self, forKey: .playlist) ?? []
        playMode = try values.decodeIfPresent(MusicPlayMode.self, forKey: .playMode) ?? .sequential
        currentTrackID = try values.decodeIfPresent(String.self, forKey: .currentTrackID)
        lastPosition = try values.decodeIfPresent(TimeInterval.self, forKey: .lastPosition) ?? 0
        favoriteTrackIDs = try values.decodeIfPresent(Set<String>.self, forKey: .favoriteTrackIDs) ?? []
        savedPlaylists = try values.decodeIfPresent([SavedMusicPlaylist].self, forKey: .savedPlaylists) ?? []
        lyricOffsets = try values.decodeIfPresent([String: TimeInterval].self, forKey: .lyricOffsets) ?? [:]
        lyricsByTrackID = try values.decodeIfPresent([String: LyricsDocument].self, forKey: .lyricsByTrackID) ?? [:]
    }
}

@MainActor
protocol MusicPlaybackControlling: AnyObject {
    func playPause()
    func pause()
    func previous()
    func next()
    func seek(to position: TimeInterval)
    func setVolume(_ volume: Double)
}
