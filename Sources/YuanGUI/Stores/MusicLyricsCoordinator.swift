import AppKit
import Foundation

@MainActor
protocol MusicLyricsCoordinatorDelegate: AnyObject {
    var lyricsCurrentTrack: MusicTrack? { get }
    var lyricsPlaybackPosition: TimeInterval { get }
    var lyricsPlaybackDuration: TimeInterval { get }

    func seekLyricsPlayback(to position: TimeInterval)
    func updateLyricsTrackMetadata(trackID: String, title: String, artist: String)
    func updateLyricsSubtitleURL(_ url: URL, trackID: String)
    func persistLyricsChanges()
    func reportLyricsError(_ message: String?)
}

@MainActor
final class MusicLyricsCoordinator {
    weak var delegate: (any MusicLyricsCoordinatorDelegate)?

    let store: LyricsStore
    let presentation: LyricsPresentationStore
    let defaults: UserDefaults
    let lyricsService: any LyricsProviding
    let localMusicImporter: any LocalMusicImporting
    let bilibili: any BilibiliMusicProviding

    var lyricLoadTask: Task<Void, Never>?
    var lyricsSearchTask: Task<Void, Never>?
    var lyricsByTrackID: [String: LyricsDocument] = [:]
    var lyricLoadRevision: UInt64 = 0
    var isShuttingDown = false

    init(
        store: LyricsStore,
        presentation: LyricsPresentationStore,
        defaults: UserDefaults,
        lyricsService: any LyricsProviding,
        localMusicImporter: any LocalMusicImporting,
        bilibili: any BilibiliMusicProviding
    ) {
        self.store = store
        self.presentation = presentation
        self.defaults = defaults
        self.lyricsService = lyricsService
        self.localMusicImporter = localMusicImporter
        self.bilibili = bilibili
    }

    func shutdown() async {
        isShuttingDown = true
        lyricLoadRevision &+= 1
        let running = [lyricLoadTask, lyricsSearchTask].compactMap { $0 }
        running.forEach { $0.cancel() }
        for task in running {
            await task.value
        }
        lyricLoadTask = nil
        lyricsSearchTask = nil
        isLoading = false
        isSearching = false
    }

    func cancelSearch() {
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
        if isSearching {
            isSearching = false
        }
    }

    func seek(to line: TimedLyricLine) {
        let target = MusicPlaybackCoordinator.lyricSeekPosition(
            for: line,
            offset: currentLyricOffset,
            duration: duration
        )
        delegate?.seekLyricsPlayback(to: target)
    }

    var currentTrack: MusicTrack? { delegate?.lyricsCurrentTrack }
    var position: TimeInterval { delegate?.lyricsPlaybackPosition ?? 0 }
    var duration: TimeInterval { delegate?.lyricsPlaybackDuration ?? 0 }
    var document: LyricsDocument? {
        get { store.document }
        set {
            store.document = newValue
            presentation.prepareChineseConversion(for: newValue)
        }
    }
    var currentLine: TimedLyricLine? {
        get { store.currentLine }
        set { store.currentLine = newValue }
    }
    var nextLine: TimedLyricLine? {
        get { store.nextLine }
        set { store.nextLine = newValue }
    }
    var currentLineIndex: Int? {
        get { store.currentLineIndex }
        set { store.currentLineIndex = newValue }
    }
    var isLoading: Bool {
        get { store.isLoading }
        set { store.isLoading = newValue }
    }
    var offsets: [String: TimeInterval] {
        get { store.offsets }
        set { store.offsets = newValue }
    }
    var isSearching: Bool {
        get { store.isSearching }
        set { store.isSearching = newValue }
    }
    var searchMessage: String? {
        get { store.searchMessage }
        set { store.searchMessage = newValue }
    }
    var currentLyricOffset: TimeInterval {
        currentTrack.flatMap { offsets[$0.id] } ?? 0
    }
    var lyrics: LyricsDocument? {
        get { document }
        set { document = newValue }
    }
    var currentLyric: TimedLyricLine? {
        get { currentLine }
        set { currentLine = newValue }
    }
    var nextLyric: TimedLyricLine? {
        get { nextLine }
        set { nextLine = newValue }
    }
    var currentLyricIndex: Int? {
        get { currentLineIndex }
        set { currentLineIndex = newValue }
    }
    var isLoadingLyrics: Bool {
        get { isLoading }
        set { isLoading = newValue }
    }
    var lyricOffsets: [String: TimeInterval] {
        get { offsets }
        set { offsets = newValue }
    }
    var isSearchingLyrics: Bool {
        get { isSearching }
        set { isSearching = newValue }
    }
    var lyricsSearchMessage: String? {
        get { searchMessage }
        set { searchMessage = newValue }
    }
    var lyricsPresentation: LyricsPresentationStore { presentation }
    var lyricsVisible: Bool {
        get { presentation.isVisible }
        set { presentation.isVisible = newValue }
    }
    var lightSingAlongEnabled: Bool {
        get { presentation.lightSingAlongEnabled }
        set { presentation.lightSingAlongEnabled = newValue }
    }
    var lyricsPanelLocked: Bool {
        get { presentation.isPanelLocked }
        set { presentation.isPanelLocked = newValue }
    }
    var lyricsFontSize: Double {
        get { presentation.fontSize }
        set { presentation.fontSize = newValue }
    }
    var lyricsFontStyle: LyricsFontStyle {
        get { presentation.fontStyle }
        set { presentation.fontStyle = newValue }
    }
    var lyricsChineseConversionMode: LyricsChineseConversionMode {
        get { presentation.chineseConversionMode }
        set { presentation.chineseConversionMode = newValue }
    }
    var lyricsColor: NSColor {
        get { presentation.color }
        set { presentation.color = newValue }
    }
    var lyricsShadowEnabled: Bool {
        get { presentation.shadowEnabled }
        set { presentation.shadowEnabled = newValue }
    }
    var lyricsBackgroundVisible: Bool {
        get { presentation.backgroundVisible }
        set { presentation.backgroundVisible = newValue }
    }
    var lyricsBackgroundOpacity: Double {
        get { presentation.backgroundOpacity }
        set { presentation.backgroundOpacity = newValue }
    }
}

extension MusicLyricsCoordinator: MusicLibraryLyricsAccess {
    var libraryLyricOffsets: [String: TimeInterval] {
        get { lyricOffsets }
        set { lyricOffsets = newValue }
    }
    var libraryLyricsCache: [String: LyricsDocument] {
        get { lyricsByTrackID }
        set { lyricsByTrackID = newValue }
    }

    func removeLibraryCachedLyrics(for track: MusicTrack) {
        removeCachedLyrics(for: track)
    }

    func resetLibraryLyrics() {
        cancelLyricLoad()
        cancelSearch()
        lyrics = nil
        currentLyric = nil
        nextLyric = nil
        currentLyricIndex = nil
    }

    func loadLibraryLyrics(for track: MusicTrack) {
        loadLyrics(for: track)
    }
}
