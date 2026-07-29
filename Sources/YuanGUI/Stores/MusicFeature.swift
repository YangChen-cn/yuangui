import AppKit
import Foundation

@MainActor
final class MusicFeature {
    private let context: MusicFeatureContext
    private let playbackCommands: MusicPlaybackCoordinator
    private let libraryCommands: MusicLibraryController
    private let lyricsCommands: MusicLyricsCoordinator
    private let bilibiliCommands: BilibiliMusicCoordinator
    private let localCommands: LocalMusicCoordinator

    var playback: MusicPlaybackStore { context.playback }
    var libraryStore: MusicLibraryStore { context.library }
    var lyricsStore: LyricsStore { context.lyrics }
    var lyricsPresentation: LyricsPresentationStore { context.lyricsPresentation }
    var bilibiliAccountStore: BilibiliAccountStore { context.bilibiliAccount }
    var bilibiliImportStore: BilibiliImportStore { context.bilibiliImport }
    var localImportStore: LocalMusicImportStore { context.localImport }

    var progress: Double { playback.fractionComplete }
    var position: TimeInterval { playback.progress.position }
    var duration: TimeInterval { playback.progress.duration }
    var source: MusicSource { playback.browsingSource }
    var playbackSource: MusicSource { playback.playbackSource }
    var isPlaying: Bool { playback.state.isPlaying }
    var canControl: Bool {
        if let activeSource = playback.activePlaybackSource {
            return activeSource == .appleMusic ? true : playback.currentTrack != nil
        }
        return source == .appleMusic
            ? true
            : playback.currentTrack != nil || !libraryStore.playlist.isEmpty
    }
    var currentLyricOffset: TimeInterval {
        playback.currentTrack.flatMap { lyricsStore.offsets[$0.id] } ?? 0
    }
    var favoriteTracks: [MusicTrack] { libraryCommands.favoriteTracks }
    var upcomingTracks: [MusicTrack] { libraryCommands.upcomingTracks }

    var onExternalAudioResumeCancelled: (() -> Void)? {
        get { playbackCommands.onExternalAudioResumeCancelled }
        set { playbackCommands.onExternalAudioResumeCancelled = newValue }
    }
    var onExternalAudioManualControl: (() -> Void)? {
        get { playbackCommands.onExternalAudioManualControl }
        set { playbackCommands.onExternalAudioManualControl = newValue }
    }
    var blocksAutomaticPlaybackForExternalAudio: (() -> Bool)? {
        get { playbackCommands.blocksAutomaticPlaybackForExternalAudio }
        set { playbackCommands.blocksAutomaticPlaybackForExternalAudio = newValue }
    }

    init(
        defaults: UserDefaults = .standard,
        appleMusic: any AppleMusicProviding = AppleMusicController(),
        bilibili: any BilibiliMusicProviding = BilibiliClient(),
        urlPlayer: (any URLMusicPlaying)? = nil,
        urlPlayerFactory: @escaping URLMusicPlayerFactory = { URLMusicPlayerEngine() },
        lyricsService: any LyricsProviding = LyricsService(),
        localMusicImporter: any LocalMusicImporting = LocalMusicImportService(),
        localArtworkRepository: any LocalMusicArtworkManaging = LocalMusicArtworkRepository.shared,
        localFileRevealer: (any LocalMusicFileRevealing)? = nil,
        library: any MusicLibraryCoordinating = MusicLibraryActor(),
        urlPlayerReleaseDelay: Duration = .seconds(60)
    ) {
        let source = MusicSource(rawValue: defaults.string(forKey: "musicSource") ?? "")
            ?? .appleMusic
        let bilibiliVolume = defaults.object(forKey: "bilibiliMusicVolume") as? Double ?? 0.8
        let localVolume = defaults.object(forKey: "localMusicVolume") as? Double ?? 0.8
        let playbackStore = MusicPlaybackStore(
            source: source,
            volume: source == .local ? localVolume : bilibiliVolume
        )
        let context = MusicFeatureContext(
            playback: playbackStore,
            library: MusicLibraryStore(),
            lyrics: LyricsStore(),
            lyricsPresentation: LyricsPresentationStore(defaults: defaults),
            bilibiliAccount: BilibiliAccountStore(),
            bilibiliImport: BilibiliImportStore(),
            localImport: LocalMusicImportStore(),
            defaults: defaults
        )
        let persistence = MusicPersistenceCoordinator(library: library)
        let playbackCommands = MusicPlaybackCoordinator(
            context: context,
            appleMusic: appleMusic,
            bilibili: bilibili,
            localMusicImporter: localMusicImporter,
            urlPlayer: urlPlayer,
            urlPlayerFactory: urlPlayerFactory,
            urlPlayerReleaseDelay: urlPlayerReleaseDelay
        )
        let libraryCommands = MusicLibraryController(
            context: context,
            persistence: persistence
        )
        let lyricsCommands = MusicLyricsCoordinator(
            context: context,
            lyricsService: lyricsService,
            localMusicImporter: localMusicImporter,
            bilibili: bilibili
        )
        let bilibiliCommands = BilibiliMusicCoordinator(
            context: context,
            bilibili: bilibili
        )
        let localCommands = LocalMusicCoordinator(
            context: context,
            importer: localMusicImporter,
            artworkRepository: localArtworkRepository,
            fileRevealer: localFileRevealer ?? WorkspaceLocalMusicFileRevealer.shared
        )
        context.bind(
            playback: playbackCommands,
            library: libraryCommands,
            lyrics: lyricsCommands,
            bilibili: bilibiliCommands,
            local: localCommands
        )
        self.context = context
        self.playbackCommands = playbackCommands
        self.libraryCommands = libraryCommands
        self.lyricsCommands = lyricsCommands
        self.bilibiliCommands = bilibiliCommands
        self.localCommands = localCommands

        playbackCommands.start()
        bilibiliCommands.start()
        libraryCommands.start()
    }

    func setSource(_ source: MusicSource) { playbackCommands.setSource(source) }
    func connectAppleMusic(autoplay: Bool = false) { playbackCommands.connectAppleMusic(autoplay: autoplay) }
    func openAppleMusic() { playbackCommands.openAppleMusic() }
    func openAutomationSettings() { playbackCommands.openAutomationSettings() }
    func playPause() { playbackCommands.playPause() }
    func previous() { playbackCommands.previous() }
    func next() { playbackCommands.next() }
    func seek(to position: TimeInterval) { playbackCommands.seek(to: position) }
    func seek(toLyric line: TimedLyricLine) { lyricsCommands.seek(to: line) }
    func setVolume(_ volume: Double) { playbackCommands.setVolume(volume) }
    func setPlayMode(_ mode: MusicPlayMode) { playbackCommands.setPlayMode(mode) }
    func play(_ track: MusicTrack, at position: TimeInterval = 0) {
        playbackCommands.play(track, at: position)
    }
    func pauseForExternalAudio() { playbackCommands.pauseForExternalAudio() }
    func resumeAfterExternalAudio() { playbackCommands.resumeAfterExternalAudio() }
    func cancelExternalAudioResume() { playbackCommands.cancelExternalAudioResume() }

    func remove(_ track: MusicTrack) { libraryCommands.remove(track) }
    func clearPlaylist() { libraryCommands.clearPlaylist() }
    func isFavorite(_ track: MusicTrack) -> Bool { libraryCommands.isFavorite(track) }
    func toggleFavorite(_ track: MusicTrack) { libraryCommands.toggleFavorite(track) }
    func createPlaylist(named name: String) -> SavedMusicPlaylist? {
        libraryCommands.createPlaylist(named: name)
    }
    func deletePlaylist(_ playlist: SavedMusicPlaylist) { libraryCommands.deletePlaylist(playlist) }
    func add(_ track: MusicTrack, to playlist: SavedMusicPlaylist) {
        libraryCommands.add(track, to: playlist)
    }
    func remove(_ track: MusicTrack, from playlist: SavedMusicPlaylist) {
        libraryCommands.remove(track, from: playlist)
    }
    func tracks(in playlist: SavedMusicPlaylist) -> [MusicTrack] {
        libraryCommands.tracks(in: playlist)
    }

    func toggleLyricsVisible() { lyricsCommands.toggleVisible() }
    func setLightSingAlongEnabled(_ enabled: Bool) { lyricsCommands.setLightSingAlongEnabled(enabled) }
    func setLyricsPanelLocked(_ locked: Bool) { lyricsCommands.setPanelLocked(locked) }
    func setLyricsFontSize(_ size: Double) { lyricsCommands.setFontSize(size) }
    func setLyricsFontStyle(_ style: LyricsFontStyle) { lyricsCommands.setFontStyle(style) }
    func setLyricsColor(_ color: NSColor) { lyricsCommands.setColor(color) }
    func setLyricsShadowEnabled(_ enabled: Bool) { lyricsCommands.setShadowEnabled(enabled) }
    func setLyricsBackgroundVisible(_ visible: Bool) { lyricsCommands.setBackgroundVisible(visible) }
    func setLyricsBackgroundOpacity(_ opacity: Double) { lyricsCommands.setBackgroundOpacity(opacity) }
    func setLyricOffset(_ offset: TimeInterval) { lyricsCommands.setOffset(offset) }
    func searchLyrics(title: String, artist: String) {
        lyricsCommands.search(title: title, artist: artist)
    }
    @discardableResult
    func updateCurrentTrackMetadata(title: String, artist: String) -> Bool {
        lyricsCommands.updateCurrentTrackMetadata(title: title, artist: artist)
    }
    func importLRC(from url: URL) { lyricsCommands.importLRC(from: url) }

    func importBilibili() { bilibiliCommands.importBilibili() }
    func playLastBilibiliImport() { bilibiliCommands.playLastBilibiliImport() }
    func dismissBilibiliImportResult() { bilibiliCommands.dismissBilibiliImportResult() }
    func loadBilibiliFavoriteFolders() { bilibiliCommands.loadBilibiliFavoriteFolders() }
    func importBilibiliFavoriteFolder(_ folder: BilibiliFavoriteFolder) {
        bilibiliCommands.importBilibiliFavoriteFolder(folder)
    }
    func cancelBilibiliFavoriteOperation() { bilibiliCommands.cancelBilibiliFavoriteOperation() }
    func refreshBilibiliAccount() { bilibiliCommands.refreshBilibiliAccount() }
    func startBilibiliLogin() { bilibiliCommands.startBilibiliLogin() }
    func cancelBilibiliLogin() { bilibiliCommands.cancelBilibiliLogin() }
    func logoutBilibili() { bilibiliCommands.logoutBilibili() }

    func importLocalMusic(_ urls: [URL]) { localCommands.importLocalMusic(urls) }
    func cancelLocalImport() { localCommands.cancelLocalImport() }
    func relocate(_ track: MusicTrack, to url: URL) { localCommands.relocate(track, to: url) }
    func revealInFinder(_ track: MusicTrack) { localCommands.revealInFinder(track) }
    func setArtwork(for track: MusicTrack, from url: URL) {
        localCommands.setArtwork(for: track, from: url)
    }
    func removeArtwork(for track: MusicTrack) { localCommands.removeArtwork(for: track) }

    func shutdown() async {
        bilibiliCommands.shutdown()
        lyricsCommands.shutdown()
        playbackCommands.shutdown()
        await libraryCommands.shutdown()
        await localCommands.shutdown()
    }

    nonisolated static func lyricSeekPosition(
        for line: TimedLyricLine,
        offset: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        MusicPlaybackCoordinator.lyricSeekPosition(
            for: line,
            offset: offset,
            duration: duration
        )
    }

    static func decodeLyricsColor(_ value: String?) -> NSColor? {
        MusicLyricsCoordinator.decodeColor(value)
    }
}
