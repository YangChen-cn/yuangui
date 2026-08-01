import AppKit
import Foundation

@MainActor
final class MusicFeature {
    private let playbackCommands: MusicPlaybackCoordinator
    private let libraryCommands: MusicLibraryController
    private let lyricsCommands: MusicLyricsCoordinator
    private let bilibiliCommands: BilibiliMusicCoordinator
    private let localCommands: LocalMusicCoordinator

    let playback: MusicPlaybackStore
    let libraryStore: MusicLibraryStore
    let lyricsStore: LyricsStore
    let lyricsPresentation: LyricsPresentationStore
    let bilibiliAccountStore: BilibiliAccountStore
    let bilibiliImportStore: BilibiliImportStore
    let localImportStore: LocalMusicImportStore

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
        let libraryStore = MusicLibraryStore()
        let lyricsStore = LyricsStore()
        let lyricsPresentation = LyricsPresentationStore(defaults: defaults)
        let bilibiliAccountStore = BilibiliAccountStore()
        let bilibiliImportStore = BilibiliImportStore()
        let localImportStore = LocalMusicImportStore()
        let persistence = MusicPersistenceCoordinator(library: library)
        let playbackCommands = MusicPlaybackCoordinator(
            playback: playbackStore,
            defaults: defaults,
            appleMusic: appleMusic,
            bilibili: bilibili,
            localMusicImporter: localMusicImporter,
            urlPlayer: urlPlayer,
            urlPlayerFactory: urlPlayerFactory,
            urlPlayerReleaseDelay: urlPlayerReleaseDelay
        )
        let libraryCommands = MusicLibraryController(
            store: libraryStore,
            persistence: persistence
        )
        let lyricsCommands = MusicLyricsCoordinator(
            store: lyricsStore,
            presentation: lyricsPresentation,
            defaults: defaults,
            lyricsService: lyricsService,
            localMusicImporter: localMusicImporter,
            bilibili: bilibili
        )
        let bilibiliCommands = BilibiliMusicCoordinator(
            accountStore: bilibiliAccountStore,
            importStore: bilibiliImportStore,
            bilibili: bilibili
        )
        let localCommands = LocalMusicCoordinator(
            importStore: localImportStore,
            importer: localMusicImporter,
            artworkRepository: localArtworkRepository,
            fileRevealer: localFileRevealer ?? WorkspaceLocalMusicFileRevealer.shared
        )
        playback = playbackStore
        self.libraryStore = libraryStore
        self.lyricsStore = lyricsStore
        self.lyricsPresentation = lyricsPresentation
        self.bilibiliAccountStore = bilibiliAccountStore
        self.bilibiliImportStore = bilibiliImportStore
        self.localImportStore = localImportStore
        self.playbackCommands = playbackCommands
        self.libraryCommands = libraryCommands
        self.lyricsCommands = lyricsCommands
        self.bilibiliCommands = bilibiliCommands
        self.localCommands = localCommands

        playbackCommands.delegate = self
        lyricsCommands.delegate = self
        bilibiliCommands.delegate = self
        localCommands.delegate = self
        libraryCommands.playbackAccess = playbackCommands
        libraryCommands.lyricsAccess = lyricsCommands
        libraryCommands.artworkAccess = localCommands

        playbackCommands.start()
        bilibiliCommands.start()
        libraryCommands.start()
    }

    func setSource(_ source: MusicSource) { playbackCommands.setSource(source) }
    func connectAppleMusic(autoplay: Bool = false) { playbackCommands.connectAppleMusic(autoplay: autoplay) }
    func resumeAppleMusicSynchronization() { playbackCommands.resumeAppleMusicSynchronization() }
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
        await bilibiliCommands.shutdown()
        await localCommands.shutdown()
        await playbackCommands.shutdown()
        await lyricsCommands.shutdown()
        await libraryCommands.shutdown()
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

extension MusicFeature: MusicPlaybackCoordinatorDelegate {
    var playbackPlaylist: [MusicTrack] { libraryStore.playlist }
    var playbackCurrentLyricOffset: TimeInterval { currentLyricOffset }

    func resetPlaybackLyrics() {
        lyricsCommands.resetLibraryLyrics()
    }

    func loadPlaybackLyrics(for track: MusicTrack) {
        lyricsCommands.loadLyrics(for: track)
    }

    func updatePlaybackLyric() {
        lyricsCommands.updateLyric()
    }

    func persistPlaybackLibrary() {
        libraryCommands.persistLibrary()
    }

    func persistPlaybackProgressIfNeeded() {
        libraryCommands.persistProgressIfNeeded()
    }

    func reportBilibiliPlaybackError(_ message: String?) {
        bilibiliImportStore.errorMessage = message
    }

    func reportLocalPlaybackError(_ message: String?, relocating track: MusicTrack?) {
        localImportStore.errorMessage = message
        localImportStore.trackNeedingRelocation = track
    }
}

extension MusicFeature: BilibiliMusicCoordinatorDelegate {
    func importBilibiliTracks(
        _ tracks: [MusicTrack],
        playlistName: String?
    ) -> [MusicTrack] {
        let added = libraryCommands.importTracks(tracks, playlistName: playlistName)
        if !added.isEmpty {
            playbackCommands.rebuildMusicPlaybackQueue()
        }
        playbackCommands.setSource(.bilibili)
        libraryCommands.persistLibrary()
        return added
    }

    func bilibiliTrack(withID id: String) -> MusicTrack? {
        libraryCommands.track(withID: id)
    }

    func playBilibiliTrack(_ track: MusicTrack) {
        playbackCommands.play(track)
    }

    func refreshCurrentBilibiliLyricsAfterLogin() async {
        await lyricsCommands.refreshCurrentBilibiliSubtitleAfterLogin()
    }
}

extension MusicFeature: LocalMusicCoordinatorDelegate {
    var localDuplicateKeys: Set<String> { libraryCommands.localDuplicateKeys }
    var referencedArtworkKeys: Set<String> { libraryCommands.referencedArtworkKeys }

    func appendImportedLocalTracks(_ tracks: [MusicTrack]) {
        libraryCommands.appendImportedLocalTracks(tracks)
    }

    func didImportLocalTracks() {
        playbackCommands.setSource(.local)
        if playback.currentTrack?.source != .local {
            playbackCommands.restoreSelection(for: .local)
        }
        playbackCommands.rebuildMusicPlaybackQueue()
        libraryCommands.persistLibrary()
    }

    func replaceLocalTrack(_ original: MusicTrack, with updated: MusicTrack) -> Bool {
        libraryCommands.replaceTrack(original, with: updated)
    }

    func didRelocateCurrentLocalTrack(_ original: MusicTrack, to updated: MusicTrack) {
        lyricsCommands.removeCachedLyrics(for: original)
        guard playback.currentTrack?.id == original.id else { return }
        playbackCommands.urlPlayer?.stop()
        playbackCommands.clearLoadedURLIdentity()
        playbackCommands.releaseScopedLocalURL()
        playback.currentTrack = updated
        playback.progress.setDuration(updated.duration)
        playback.progress.setPosition(min(position, updated.duration))
        playbackCommands.setPlaybackState(.paused)
        lyricsCommands.loadLyrics(for: updated)
    }

    func replaceArtwork(
        for trackID: String,
        with newKey: String
    ) -> (didReplace: Bool, previousKey: String?) {
        libraryCommands.replaceArtwork(for: trackID, with: newKey)
    }

    func removeArtwork(for trackID: String) -> String? {
        libraryCommands.removeArtwork(for: trackID)
    }

    func persistLocalMusicChanges() {
        libraryCommands.persistLibrary()
    }
}

extension MusicFeature: MusicLyricsCoordinatorDelegate {
    var lyricsCurrentTrack: MusicTrack? { playback.currentTrack }
    var lyricsPlaybackPosition: TimeInterval { position }
    var lyricsPlaybackDuration: TimeInterval { duration }

    func seekLyricsPlayback(to position: TimeInterval) {
        playbackCommands.seek(to: position)
    }

    func updateLyricsTrackMetadata(trackID: String, title: String, artist: String) {
        if libraryCommands.track(withID: trackID) != nil {
            libraryCommands.updateTrackMetadata(
                trackID: trackID,
                title: title,
                artist: artist
            )
        } else if playback.currentTrack?.id == trackID {
            playback.currentTrack?.title = title
            playback.currentTrack?.artist = artist
        }
    }

    func updateLyricsSubtitleURL(_ url: URL, trackID: String) {
        if libraryCommands.track(withID: trackID) != nil {
            libraryCommands.updateSubtitleURL(url, trackID: trackID)
        } else if playback.currentTrack?.id == trackID {
            playback.currentTrack?.subtitleURL = url
        }
    }

    func persistLyricsChanges() {
        libraryCommands.persistLibrary()
    }

    func reportLyricsError(_ message: String?) {
        bilibiliImportStore.errorMessage = message
    }
}
