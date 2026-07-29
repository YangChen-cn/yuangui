import AppKit
import Foundation

@MainActor
class MusicDomainCoordinator {
    let context: MusicFeatureContext

    init(context: MusicFeatureContext) {
        self.context = context
    }

    var playback: MusicPlaybackStore { context.playback }
    var libraryStore: MusicLibraryStore { context.library }
    var lyricsStore: LyricsStore { context.lyrics }
    var lyricsPresentation: LyricsPresentationStore { context.lyricsPresentation }
    var bilibiliAccountStore: BilibiliAccountStore { context.bilibiliAccount }
    var bilibiliImportStore: BilibiliImportStore { context.bilibiliImport }
    var localImportStore: LocalMusicImportStore { context.localImport }
    var defaults: UserDefaults { context.defaults }

    var browsingSource: MusicSource {
        get { playback.browsingSource }
        set { playback.browsingSource = newValue }
    }
    var activePlaybackSource: MusicSource? {
        get { playback.activePlaybackSource }
        set { playback.activePlaybackSource = newValue }
    }
    var playbackState: MusicPlaybackState {
        get { playback.state }
        set { playback.state = newValue }
    }
    var currentTrack: MusicTrack? {
        get { playback.currentTrack }
        set { playback.currentTrack = newValue }
    }
    var volume: Double {
        get { playback.volume }
        set { playback.volume = newValue }
    }
    var upcomingTrackIDs: [String] {
        get { playback.upcomingTrackIDs }
        set { playback.upcomingTrackIDs = newValue }
    }
    var playMode: MusicPlayMode {
        get { playback.playMode }
        set { playback.playMode = newValue }
    }
    var appleMusicRunning: Bool {
        get { playback.appleMusicRunning }
        set { playback.appleMusicRunning = newValue }
    }
    var playbackProgress: MusicPlaybackProgress { playback.progress }
    var playlist: [MusicTrack] {
        get { libraryStore.playlist }
        set { libraryStore.playlist = newValue }
    }
    var favoriteTrackIDs: Set<String> {
        get { libraryStore.favoriteTrackIDs }
        set { libraryStore.favoriteTrackIDs = newValue }
    }
    var savedPlaylists: [SavedMusicPlaylist] {
        get { libraryStore.savedPlaylists }
        set { libraryStore.savedPlaylists = newValue }
    }
    var lyrics: LyricsDocument? {
        get { lyricsStore.document }
        set { lyricsStore.document = newValue }
    }
    var currentLyric: TimedLyricLine? {
        get { lyricsStore.currentLine }
        set { lyricsStore.currentLine = newValue }
    }
    var nextLyric: TimedLyricLine? {
        get { lyricsStore.nextLine }
        set { lyricsStore.nextLine = newValue }
    }
    var currentLyricIndex: Int? {
        get { lyricsStore.currentLineIndex }
        set { lyricsStore.currentLineIndex = newValue }
    }
    var isLoadingLyrics: Bool {
        get { lyricsStore.isLoading }
        set { lyricsStore.isLoading = newValue }
    }
    var lyricOffsets: [String: TimeInterval] {
        get { lyricsStore.offsets }
        set { lyricsStore.offsets = newValue }
    }
    var isSearchingLyrics: Bool {
        get { lyricsStore.isSearching }
        set { lyricsStore.isSearching = newValue }
    }
    var lyricsSearchMessage: String? {
        get { lyricsStore.searchMessage }
        set { lyricsStore.searchMessage = newValue }
    }
    var lyricsVisible: Bool {
        get { lyricsPresentation.isVisible }
        set { lyricsPresentation.isVisible = newValue }
    }
    var lightSingAlongEnabled: Bool {
        get { lyricsPresentation.lightSingAlongEnabled }
        set { lyricsPresentation.lightSingAlongEnabled = newValue }
    }
    var lyricsPanelLocked: Bool {
        get { lyricsPresentation.isPanelLocked }
        set { lyricsPresentation.isPanelLocked = newValue }
    }
    var lyricsFontSize: Double {
        get { lyricsPresentation.fontSize }
        set { lyricsPresentation.fontSize = newValue }
    }
    var lyricsFontStyle: LyricsFontStyle {
        get { lyricsPresentation.fontStyle }
        set { lyricsPresentation.fontStyle = newValue }
    }
    var lyricsColor: NSColor {
        get { lyricsPresentation.color }
        set { lyricsPresentation.color = newValue }
    }
    var lyricsShadowEnabled: Bool {
        get { lyricsPresentation.shadowEnabled }
        set { lyricsPresentation.shadowEnabled = newValue }
    }
    var lyricsBackgroundVisible: Bool {
        get { lyricsPresentation.backgroundVisible }
        set { lyricsPresentation.backgroundVisible = newValue }
    }
    var lyricsBackgroundOpacity: Double {
        get { lyricsPresentation.backgroundOpacity }
        set { lyricsPresentation.backgroundOpacity = newValue }
    }
    var bilibiliAccount: BilibiliAccount? {
        get { bilibiliAccountStore.account }
        set { bilibiliAccountStore.account = newValue }
    }
    var bilibiliLoginPhase: BilibiliLoginPhase {
        get { bilibiliAccountStore.loginPhase }
        set { bilibiliAccountStore.loginPhase = newValue }
    }
    var bilibiliQRCodeURL: String? {
        get { bilibiliAccountStore.qrCodeURL }
        set { bilibiliAccountStore.qrCodeURL = newValue }
    }
    var importText: String {
        get { bilibiliImportStore.input }
        set { bilibiliImportStore.input = newValue }
    }
    var isImporting: Bool {
        get { bilibiliImportStore.isImporting }
        set { bilibiliImportStore.isImporting = newValue }
    }
    var bilibiliImportMessage: String? {
        get { bilibiliImportStore.importMessage }
        set { bilibiliImportStore.importMessage = newValue }
    }
    var errorMessage: String? {
        get { bilibiliImportStore.errorMessage }
        set { bilibiliImportStore.errorMessage = newValue }
    }
    var bilibiliFavoriteFolders: [BilibiliFavoriteFolder] {
        get { bilibiliImportStore.favoriteFolders }
        set { bilibiliImportStore.favoriteFolders = newValue }
    }
    var isLoadingBilibiliFavoriteFolders: Bool {
        get { bilibiliImportStore.isLoadingFavoriteFolders }
        set { bilibiliImportStore.isLoadingFavoriteFolders = newValue }
    }
    var isImportingBilibiliFavoriteFolder: Bool {
        get { bilibiliImportStore.isImportingFavoriteFolder }
        set { bilibiliImportStore.isImportingFavoriteFolder = newValue }
    }
    var bilibiliFavoriteImportCompleted: Int {
        get { bilibiliImportStore.completedCount }
        set { bilibiliImportStore.completedCount = newValue }
    }
    var bilibiliFavoriteImportTotal: Int {
        get { bilibiliImportStore.totalCount }
        set { bilibiliImportStore.totalCount = newValue }
    }
    var bilibiliFavoriteMessage: String? {
        get { bilibiliImportStore.favoriteMessage }
        set { bilibiliImportStore.favoriteMessage = newValue }
    }
    var position: TimeInterval { playbackProgress.position }
    var duration: TimeInterval { playbackProgress.duration }
    var playbackSource: MusicSource {
        activePlaybackSource ?? currentTrack?.source ?? browsingSource
    }
    var isPlaying: Bool { playbackState.isPlaying }
    var currentLyricOffset: TimeInterval {
        currentTrack.flatMap { lyricOffsets[$0.id] } ?? 0
    }

    var playbackDomain: MusicPlaybackCoordinator { context.playbackCoordinator }
    var libraryDomain: MusicLibraryController { context.libraryController }
    var lyricsDomain: MusicLyricsCoordinator { context.lyricsCoordinator }
    var bilibiliDomain: BilibiliMusicCoordinator { context.bilibiliCoordinator }
    var localDomain: LocalMusicCoordinator { context.localCoordinator }
}
