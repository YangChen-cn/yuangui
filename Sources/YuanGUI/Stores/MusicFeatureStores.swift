import AppKit
import Foundation
import SwiftUI

@propertyWrapper
struct ObservedMusicFeature: DynamicProperty {
    let wrappedValue: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var library: MusicLibraryStore
    @ObservedObject private var lyrics: LyricsStore
    @ObservedObject private var presentation: LyricsPresentationStore
    @ObservedObject private var account: BilibiliAccountStore
    @ObservedObject private var importer: BilibiliImportStore

    init(wrappedValue: MusicFeature) {
        self.wrappedValue = wrappedValue
        _playback = ObservedObject(wrappedValue: wrappedValue.playback)
        _library = ObservedObject(wrappedValue: wrappedValue.libraryStore)
        _lyrics = ObservedObject(wrappedValue: wrappedValue.lyricsStore)
        _presentation = ObservedObject(wrappedValue: wrappedValue.lyricsPresentation)
        _account = ObservedObject(wrappedValue: wrappedValue.bilibiliAccountStore)
        _importer = ObservedObject(wrappedValue: wrappedValue.bilibiliImportStore)
    }
}

@MainActor
final class MusicPlaybackStore: ObservableObject {
    @Published var browsingSource: MusicSource
    @Published var activePlaybackSource: MusicSource?
    @Published var state: MusicPlaybackState = .stopped
    @Published var currentTrack: MusicTrack?
    @Published var volume: Double
    @Published var upcomingTrackIDs: [String] = []
    @Published var playMode: MusicPlayMode = .sequential
    @Published var appleMusicRunning = false
    let progress = MusicPlaybackProgress()

    init(source: MusicSource, volume: Double) {
        browsingSource = source
        self.volume = volume
    }

    var source: MusicSource { browsingSource }
    var playbackSource: MusicSource { activePlaybackSource ?? currentTrack?.source ?? browsingSource }
    var isPlaying: Bool { state.isPlaying }
    var position: TimeInterval { progress.position }
    var duration: TimeInterval { progress.duration }
    var fractionComplete: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }
}

@MainActor
final class MusicLibraryStore: ObservableObject {
    @Published var playlist: [MusicTrack] = []
    @Published var favoriteTrackIDs: Set<String> = []
    @Published var savedPlaylists: [SavedMusicPlaylist] = []

    var favoriteTracks: [MusicTrack] {
        playlist.filter { favoriteTrackIDs.contains($0.id) }
    }

    func tracks(in savedPlaylist: SavedMusicPlaylist) -> [MusicTrack] {
        let byID = Dictionary(uniqueKeysWithValues: playlist.map { ($0.id, $0) })
        return savedPlaylist.trackIDs.compactMap { byID[$0] }
    }
}

@MainActor
final class LyricsStore: ObservableObject {
    @Published var document: LyricsDocument?
    @Published var currentLine: TimedLyricLine?
    @Published var nextLine: TimedLyricLine?
    @Published var currentLineIndex: Int?
    @Published var isLoading = false
    @Published var offsets: [String: TimeInterval] = [:]
    @Published var isSearching = false
    @Published var searchMessage: String?
}

@MainActor
final class LyricsPresentationStore: ObservableObject {
    @Published var isVisible: Bool
    @Published var lightSingAlongEnabled: Bool
    @Published var isPanelLocked: Bool
    @Published var fontSize: Double
    @Published var fontStyle: LyricsFontStyle
    @Published var color: NSColor
    @Published var shadowEnabled: Bool
    @Published var backgroundVisible: Bool
    var onVisibilityChanged: (() -> Void)?
    var onLockChanged: (() -> Void)?

    init(defaults: UserDefaults) {
        isVisible = defaults.bool(forKey: "musicLyricsVisible")
        lightSingAlongEnabled = defaults.object(forKey: "musicLightSingAlong") == nil
            ? true
            : defaults.bool(forKey: "musicLightSingAlong")
        isPanelLocked = defaults.bool(forKey: "musicLyricsPanelLocked")
        fontSize = min(max(defaults.object(forKey: "musicLyricsFontSize") as? Double ?? 21, 14), 42)
        fontStyle = LyricsFontStyle(rawValue: defaults.string(forKey: "musicLyricsFontStyle") ?? "") ?? .rounded
        color = MusicFeature.decodeLyricsColor(defaults.string(forKey: "musicLyricsColor")) ?? .white
        shadowEnabled = defaults.object(forKey: "musicLyricsShadowEnabled") == nil
            ? true
            : defaults.bool(forKey: "musicLyricsShadowEnabled")
        backgroundVisible = defaults.bool(forKey: "musicLyricsBackgroundVisible")
    }
}

@MainActor
final class BilibiliAccountStore: ObservableObject {
    @Published var account: BilibiliAccount?
    @Published var loginPhase: BilibiliLoginPhase = .loggedOut
    @Published var qrCodeURL: String?
}

@MainActor
final class BilibiliImportStore: ObservableObject {
    @Published var input = ""
    @Published var isImporting = false
    @Published var importMessage: String?
    @Published var errorMessage: String?
    @Published var favoriteFolders: [BilibiliFavoriteFolder] = []
    @Published var isLoadingFavoriteFolders = false
    @Published var isImportingFavoriteFolder = false
    @Published var completedCount = 0
    @Published var totalCount = 0
    @Published var favoriteMessage: String?
}
