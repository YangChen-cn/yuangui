import AppKit
import Combine
import Foundation

typealias BilibiliPlayerFactory = @MainActor () -> any BilibiliPlaying

@MainActor
final class MusicPlaybackProgress: ObservableObject {
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    func setPosition(_ position: TimeInterval) {
        guard self.position != position else { return }
        self.position = position
    }

    func setDuration(_ duration: TimeInterval) {
        guard self.duration != duration else { return }
        self.duration = duration
    }

    func reset(position: TimeInterval = 0, duration: TimeInterval = 0) {
        setPosition(position)
        setDuration(duration)
    }
}

@MainActor
final class MusicFeature {
    let playback: MusicPlaybackStore
    let libraryStore: MusicLibraryStore
    let lyricsStore: LyricsStore
    let lyricsPresentation: LyricsPresentationStore
    let bilibiliAccountStore: BilibiliAccountStore
    let bilibiliImportStore: BilibiliImportStore
    let localImportStore: LocalMusicImportStore
    private let appleMusic: any AppleMusicProviding
    private let bilibili: any BilibiliMusicProviding
    private let bilibiliAccountService = BilibiliAccountService()
    private let bilibiliFavoritesService = BilibiliFavoritesService()
    private let makeBilibiliPlayer: BilibiliPlayerFactory
    private var bilibiliPlayer: (any BilibiliPlaying)?
    private var bilibiliPlayerReleaseTask: Task<Void, Never>?
    private let bilibiliPlayerReleaseDelay: Duration
    private let lyricsService: any LyricsProviding
    private let localMusicImporter: any LocalMusicImporting
    private let library: any MusicLibraryCoordinating
    private let defaults: UserDefaults
    private var libraryRestoreTask: Task<Void, Never>?
    private var appleSyncTask: Task<Void, Never>?
    private var appleClockTask: Task<Void, Never>?
    private var appleSyncGeneration: UInt = 0
    private var appleClockGeneration: UInt = 0
    private var appleRefreshTask: Task<Void, Never>?
    private var appleArtworkTask: Task<Void, Never>?
    private var bilibiliImportResultTask: Task<Void, Never>?
    private var lyricLoadTask: Task<Void, Never>?
    private var lyricsSearchTask: Task<Void, Never>?
    private var bilibiliLoadTask: Task<Void, Never>?
    private var bilibiliLoginTask: Task<Void, Never>?
    private var bilibiliFavoriteTask: Task<Void, Never>?
    private var localImportTask: Task<Void, Never>?
    private var localLoadTask: Task<Void, Never>?
    private var lyricsByTrackID: [String: LyricsDocument] = [:]
    private var currentTrackID: String?
    private var lastSavedSecond = -1
    private var lastBilibiliPosition: TimeInterval = 0
    private var bilibiliRefreshAttempted = false
    private var bilibiliVolume: Double
    private var localVolume: Double
    private var lastImportedTrackID: String?
    private var persistenceRevision: UInt64 = 0
    private var lyricLoadRevision: UInt64 = 0
    private var lastAppleClockTime: TimeInterval?
    private var bilibiliPlaybackQueue = BilibiliPlaybackQueue()
    private var appleMusicWorkspaceObservers: [NSObjectProtocol] = []
    private var pausedForExternalAudio = false
    private var scopedLocalURL: URL?
    var onExternalAudioResumeCancelled: (() -> Void)?
    var onExternalAudioManualControl: (() -> Void)?
    var blocksAutomaticPlaybackForExternalAudio: (() -> Bool)?

    init(
        defaults: UserDefaults = .standard,
        appleMusic: any AppleMusicProviding = AppleMusicController(),
        bilibili: any BilibiliMusicProviding = BilibiliClient(),
        bilibiliPlayer: (any BilibiliPlaying)? = nil,
        bilibiliPlayerFactory: @escaping BilibiliPlayerFactory = { BilibiliPlayerEngine() },
        lyricsService: any LyricsProviding = LyricsService(),
        localMusicImporter: any LocalMusicImporting = LocalMusicImportService(),
        library: any MusicLibraryCoordinating = MusicLibraryActor(),
        bilibiliPlayerReleaseDelay: Duration = .seconds(60)
    ) {
        let source = MusicSource(rawValue: defaults.string(forKey: "musicSource") ?? "") ?? .appleMusic
        let savedBilibiliVolume = defaults.object(forKey: "bilibiliMusicVolume") as? Double ?? 0.8
        let savedLocalVolume = defaults.object(forKey: "localMusicVolume") as? Double ?? 0.8
        self.defaults = defaults
        self.appleMusic = appleMusic
        self.bilibili = bilibili
        self.bilibiliPlayer = bilibiliPlayer
        self.makeBilibiliPlayer = bilibiliPlayerFactory
        self.bilibiliPlayerReleaseDelay = bilibiliPlayerReleaseDelay
        self.lyricsService = lyricsService
        self.localMusicImporter = localMusicImporter
        self.library = library
        playback = MusicPlaybackStore(
            source: source,
            volume: source == .local ? savedLocalVolume : savedBilibiliVolume
        )
        libraryStore = MusicLibraryStore()
        lyricsStore = LyricsStore()
        lyricsPresentation = LyricsPresentationStore(defaults: defaults)
        bilibiliAccountStore = BilibiliAccountStore()
        bilibiliImportStore = BilibiliImportStore()
        localImportStore = LocalMusicImportStore()
        self.bilibiliVolume = savedBilibiliVolume
        self.localVolume = savedLocalVolume
        if let bilibiliPlayer { configureBilibiliPlayer(bilibiliPlayer) }
        installAppleMusicWorkspaceObservers()
        refreshBilibiliAccount()
        libraryRestoreTask = Task { [weak self] in
            await self?.restoreLibrary()
        }
    }

    private func configureBilibiliPlayer(_ player: any BilibiliPlaying) {
        player.setVolume(bilibiliVolume)
        player.onStateChange = { [weak self] state in
            guard let self, self.activePlaybackSource == .bilibili || self.activePlaybackSource == .local else { return }
            if self.playbackState != state { self.setPlaybackState(state) }
        }
        player.onProgress = { [weak self] position, duration in
            guard let self, self.activePlaybackSource == .bilibili || self.activePlaybackSource == .local else { return }
            self.playbackProgress.setPosition(position)
            if self.activePlaybackSource == .bilibili { self.lastBilibiliPosition = position }
            if duration > 0 { self.playbackProgress.setDuration(duration) }
            self.updateLyric()
            self.persistProgressIfNeeded()
        }
        player.onFinished = { [weak self] in self?.handleTrackFinished() }
        player.onFailure = { [weak self] error in self?.handleURLPlayerFailure(error) }
    }

    private func ensureBilibiliPlayer() -> any BilibiliPlaying {
        bilibiliPlayerReleaseTask?.cancel()
        bilibiliPlayerReleaseTask = nil
        if let bilibiliPlayer { return bilibiliPlayer }
        let player = makeBilibiliPlayer()
        configureBilibiliPlayer(player)
        bilibiliPlayer = player
        return player
    }

    private func unloadBilibiliPlayer() {
        releaseScopedLocalURL()
        bilibiliPlayer?.onStateChange = nil
        bilibiliPlayer?.onProgress = nil
        bilibiliPlayer?.onFinished = nil
        bilibiliPlayer?.onFailure = nil
        bilibiliPlayer?.stop()
        bilibiliPlayer = nil
    }

    private func scheduleBilibiliPlayerRelease() {
        guard bilibiliPlayer != nil else { return }
        bilibiliPlayerReleaseTask?.cancel()
        let releaseDelay = bilibiliPlayerReleaseDelay
        bilibiliPlayerReleaseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: releaseDelay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.bilibiliPlayerReleaseTask = nil
            guard self.activePlaybackSource != .bilibili else { return }
            self.unloadBilibiliPlayer()
        }
    }

    private var browsingSource: MusicSource {
        get { playback.browsingSource }
        set { playback.browsingSource = newValue }
    }
    private var activePlaybackSource: MusicSource? {
        get { playback.activePlaybackSource }
        set { playback.activePlaybackSource = newValue }
    }
    private var playbackState: MusicPlaybackState {
        get { playback.state }
        set { playback.state = newValue }
    }

    private func setPlaybackState(_ state: MusicPlaybackState) {
        playbackState = state
        guard activePlaybackSource == .appleMusic else { return }
        if state.isPlaying {
            startAppleClockIfNeeded()
        } else {
            stopAppleClock()
        }
    }
    private var currentTrack: MusicTrack? {
        get { playback.currentTrack }
        set { playback.currentTrack = newValue }
    }
    private var volume: Double {
        get { playback.volume }
        set { playback.volume = newValue }
    }
    private var upcomingTrackIDs: [String] {
        get { playback.upcomingTrackIDs }
        set { playback.upcomingTrackIDs = newValue }
    }
    private var playMode: MusicPlayMode {
        get { playback.playMode }
        set { playback.playMode = newValue }
    }
    private var appleMusicRunning: Bool {
        get { playback.appleMusicRunning }
        set { playback.appleMusicRunning = newValue }
    }
    private var playbackProgress: MusicPlaybackProgress { playback.progress }
    private var playlist: [MusicTrack] {
        get { libraryStore.playlist }
        set { libraryStore.playlist = newValue }
    }
    private var favoriteTrackIDs: Set<String> {
        get { libraryStore.favoriteTrackIDs }
        set { libraryStore.favoriteTrackIDs = newValue }
    }
    private var savedPlaylists: [SavedMusicPlaylist] {
        get { libraryStore.savedPlaylists }
        set { libraryStore.savedPlaylists = newValue }
    }
    private var lyrics: LyricsDocument? {
        get { lyricsStore.document }
        set { lyricsStore.document = newValue }
    }
    private var currentLyric: TimedLyricLine? {
        get { lyricsStore.currentLine }
        set { lyricsStore.currentLine = newValue }
    }
    private var nextLyric: TimedLyricLine? {
        get { lyricsStore.nextLine }
        set { lyricsStore.nextLine = newValue }
    }
    private var currentLyricIndex: Int? {
        get { lyricsStore.currentLineIndex }
        set { lyricsStore.currentLineIndex = newValue }
    }
    private var isLoadingLyrics: Bool {
        get { lyricsStore.isLoading }
        set { lyricsStore.isLoading = newValue }
    }
    private var lyricOffsets: [String: TimeInterval] {
        get { lyricsStore.offsets }
        set { lyricsStore.offsets = newValue }
    }
    private var isSearchingLyrics: Bool {
        get { lyricsStore.isSearching }
        set { lyricsStore.isSearching = newValue }
    }
    private var lyricsSearchMessage: String? {
        get { lyricsStore.searchMessage }
        set { lyricsStore.searchMessage = newValue }
    }
    private var lyricsVisible: Bool {
        get { lyricsPresentation.isVisible }
        set { lyricsPresentation.isVisible = newValue }
    }
    private var lightSingAlongEnabled: Bool {
        get { lyricsPresentation.lightSingAlongEnabled }
        set { lyricsPresentation.lightSingAlongEnabled = newValue }
    }
    private var lyricsPanelLocked: Bool {
        get { lyricsPresentation.isPanelLocked }
        set { lyricsPresentation.isPanelLocked = newValue }
    }
    private var lyricsFontSize: Double {
        get { lyricsPresentation.fontSize }
        set { lyricsPresentation.fontSize = newValue }
    }
    private var lyricsFontStyle: LyricsFontStyle {
        get { lyricsPresentation.fontStyle }
        set { lyricsPresentation.fontStyle = newValue }
    }
    private var lyricsColor: NSColor {
        get { lyricsPresentation.color }
        set { lyricsPresentation.color = newValue }
    }
    private var lyricsShadowEnabled: Bool {
        get { lyricsPresentation.shadowEnabled }
        set { lyricsPresentation.shadowEnabled = newValue }
    }
    private var lyricsBackgroundVisible: Bool {
        get { lyricsPresentation.backgroundVisible }
        set { lyricsPresentation.backgroundVisible = newValue }
    }
    private var lyricsBackgroundOpacity: Double {
        get { lyricsPresentation.backgroundOpacity }
        set { lyricsPresentation.backgroundOpacity = newValue }
    }
    private var bilibiliAccount: BilibiliAccount? {
        get { bilibiliAccountStore.account }
        set { bilibiliAccountStore.account = newValue }
    }
    private var bilibiliLoginPhase: BilibiliLoginPhase {
        get { bilibiliAccountStore.loginPhase }
        set { bilibiliAccountStore.loginPhase = newValue }
    }
    private var bilibiliQRCodeURL: String? {
        get { bilibiliAccountStore.qrCodeURL }
        set { bilibiliAccountStore.qrCodeURL = newValue }
    }
    private var importText: String {
        get { bilibiliImportStore.input }
        set { bilibiliImportStore.input = newValue }
    }
    private var isImporting: Bool {
        get { bilibiliImportStore.isImporting }
        set { bilibiliImportStore.isImporting = newValue }
    }
    private var bilibiliImportMessage: String? {
        get { bilibiliImportStore.importMessage }
        set { bilibiliImportStore.importMessage = newValue }
    }
    private var errorMessage: String? {
        get { bilibiliImportStore.errorMessage }
        set { bilibiliImportStore.errorMessage = newValue }
    }
    private var bilibiliFavoriteFolders: [BilibiliFavoriteFolder] {
        get { bilibiliImportStore.favoriteFolders }
        set { bilibiliImportStore.favoriteFolders = newValue }
    }
    private var isLoadingBilibiliFavoriteFolders: Bool {
        get { bilibiliImportStore.isLoadingFavoriteFolders }
        set { bilibiliImportStore.isLoadingFavoriteFolders = newValue }
    }
    private var isImportingBilibiliFavoriteFolder: Bool {
        get { bilibiliImportStore.isImportingFavoriteFolder }
        set { bilibiliImportStore.isImportingFavoriteFolder = newValue }
    }
    private var bilibiliFavoriteImportCompleted: Int {
        get { bilibiliImportStore.completedCount }
        set { bilibiliImportStore.completedCount = newValue }
    }
    private var bilibiliFavoriteImportTotal: Int {
        get { bilibiliImportStore.totalCount }
        set { bilibiliImportStore.totalCount = newValue }
    }
    private var bilibiliFavoriteMessage: String? {
        get { bilibiliImportStore.favoriteMessage }
        set { bilibiliImportStore.favoriteMessage = newValue }
    }

    var progress: Double { playback.fractionComplete }
    var position: TimeInterval { playbackProgress.position }
    var duration: TimeInterval { playbackProgress.duration }
    var source: MusicSource { browsingSource }
    var playbackSource: MusicSource { activePlaybackSource ?? currentTrack?.source ?? browsingSource }
    var isPlaying: Bool { playbackState.isPlaying }
    var canControl: Bool {
        if let activePlaybackSource {
            return activePlaybackSource == .appleMusic ? true : currentTrack != nil
        }
        return browsingSource == .appleMusic ? true : currentTrack != nil || !playlist.isEmpty
    }
    var currentLyricOffset: TimeInterval { currentTrack.flatMap { lyricOffsets[$0.id] } ?? 0 }

    func setSource(_ newSource: MusicSource) {
        guard newSource != browsingSource else { return }
        registerManualPlaybackControl()
        browsingSource = newSource
        defaults.set(newSource.rawValue, forKey: "musicSource")
        if newSource == .bilibili {
            // Changing the source is also a handoff of transport ownership.
            // Keep the status panel on the last Bilibili selection rather than
            // leaving the old Apple Music metadata visible.
            if activePlaybackSource != nil, activePlaybackSource != .bilibili {
                _ = activatePlaybackSource(.bilibili)
            }
            if currentTrack?.source != .bilibili { restoreBilibiliSelection() }
        } else if newSource == .local {
            if activePlaybackSource != nil { _ = activatePlaybackSource(.local) }
            if currentTrack?.source != .local { restoreSelection(for: .local) }
        } else if newSource == .appleMusic {
            if activePlaybackSource != nil { _ = activatePlaybackSource(.appleMusic) }
            if currentTrack?.source != .appleMusic { clearTransientPlaybackState() }
        }
        rebuildBilibiliPlaybackQueue()
    }

    @discardableResult
    private func activatePlaybackSource(_ newSource: MusicSource) -> Bool {
        guard activePlaybackSource != newSource else { return false }
        switch activePlaybackSource {
        case .appleMusic:
            stopAppleSyncTask()
            stopAppleClock()
        case .bilibili:
            lastBilibiliPosition = position
            bilibiliLoadTask?.cancel()
            bilibiliLoadTask = nil
            bilibiliPlayer?.pause()
            scheduleBilibiliPlayerRelease()
        case .local:
            localLoadTask?.cancel()
            localLoadTask = nil
            bilibiliPlayer?.pause()
            releaseScopedLocalURL()
        case nil:
            break
        }
        switch newSource {
        case .appleMusic:
            break
        case .local:
            Task { [appleMusic] in await appleMusic.pause() }
            if volume != localVolume { volume = localVolume }
            bilibiliPlayer?.setVolume(localVolume)
        case .bilibili:
            Task { [appleMusic] in await appleMusic.pause() }
            if volume != bilibiliVolume { volume = bilibiliVolume }
            bilibiliPlayer?.setVolume(bilibiliVolume)
        }
        activePlaybackSource = newSource
        return true
    }

    private func clearTransientPlaybackState() {
        currentTrack = nil
        playbackProgress.reset()
        setPlaybackState(.stopped)
        lyrics = nil
        currentLyric = nil
        nextLyric = nil
        currentLyricIndex = nil
        errorMessage = nil
        lyricsSearchMessage = nil
        isSearchingLyrics = false
        cancelLyricLoad()
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
    }

    func connectAppleMusic(autoplay: Bool = false) {
        registerManualPlaybackControl()
        setSource(.appleMusic)
        if activatePlaybackSource(.appleMusic) { clearTransientPlaybackState() }
        if !appleMusicRunning {
            openAppleMusic()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.finishAppleMusicConnection(autoplay: autoplay)
            }
        } else {
            finishAppleMusicConnection(autoplay: autoplay)
        }
    }

    private func finishAppleMusicConnection(autoplay: Bool) {
        Task { [weak self] in
            guard let self, activePlaybackSource == .appleMusic else { return }
            await refreshAppleMusic()
            guard activePlaybackSource == .appleMusic else { return }
            if appleMusicRunning { startAppleSyncTask() }
            if autoplay, appleMusicRunning, !playbackState.isPlaying {
                lastAppleClockTime = Date.timeIntervalSinceReferenceDate
                setPlaybackState(.playing)
                await appleMusic.playPause()
                scheduleAppleRefresh()
            }
        }
    }

    func openAppleMusic() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Music.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func playPause() {
        registerManualPlaybackControl()
        errorMessage = nil
        guard let activePlaybackSource else {
            if browsingSource != .appleMusic {
                if let currentTrack, currentTrack.source == browsingSource { play(currentTrack, at: position) }
                else if let first = playlist.first(where: { $0.source == browsingSource }) { play(first) }
            } else {
                connectAppleMusic(autoplay: true)
            }
            return
        }
        switch activePlaybackSource {
        case .appleMusic:
            guard appleMusicRunning else { connectAppleMusic(autoplay: true); return }
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            setPlaybackState(playbackState.isPlaying ? .paused : .playing)
            Task { [weak self, appleMusic] in
                await appleMusic.playPause()
                self?.scheduleAppleRefresh()
            }
        case .bilibili:
            guard let bilibiliPlayer else {
                if let currentTrack { play(currentTrack, at: position) }
                else if let first = playlist.first { play(first) }
                return
            }
            if let currentTrack, !bilibiliPlayer.hasLoadedItem {
                play(currentTrack, at: position)
            } else if currentTrack == nil, let first = playlist.first {
                play(first)
            } else {
                bilibiliPlayer.playPause()
            }
        case .local:
            guard let bilibiliPlayer else {
                if let currentTrack, currentTrack.source == .local { play(currentTrack, at: position) }
                else if let first = playlist.first(where: { $0.source == .local }) { play(first) }
                return
            }
            if let currentTrack, !bilibiliPlayer.hasLoadedItem {
                play(currentTrack, at: position)
            } else {
                bilibiliPlayer.playPause()
            }
        }
    }

    func previous() { registerManualPlaybackControl(); move(by: -1) }
    func next() { registerManualPlaybackControl(); move(by: 1) }

    func seek(to newPosition: TimeInterval) {
        registerManualPlaybackControl()
        let lowerBounded = max(newPosition, 0)
        let target = duration > 0 ? min(lowerBounded, duration) : lowerBounded
        playbackProgress.setPosition(target)
        if playbackSource == .bilibili { lastBilibiliPosition = target }
        if playbackSource == .appleMusic {
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            Task { [appleMusic] in await appleMusic.seek(to: target) }
        } else if playbackSource == .bilibili || playbackSource == .local {
            bilibiliPlayer?.seek(to: target)
        }
        updateLyric()
    }

    func seek(toLyric line: TimedLyricLine) {
        seek(to: Self.lyricSeekPosition(for: line, offset: currentLyricOffset, duration: duration))
    }

    nonisolated static func lyricSeekPosition(
        for line: TimedLyricLine,
        offset: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        let target = max(0, line.time + offset)
        return duration > 0 ? min(target, duration) : target
    }

    func setVolume(_ newValue: Double) {
        volume = min(max(newValue, 0), 1)
        if playbackSource == .appleMusic {
            Task { [appleMusic, volume] in await appleMusic.setVolume(volume) }
        } else if playbackSource == .bilibili {
            bilibiliVolume = volume
            bilibiliPlayer?.setVolume(volume)
            defaults.set(volume, forKey: "bilibiliMusicVolume")
        } else {
            localVolume = volume
            bilibiliPlayer?.setVolume(volume)
            defaults.set(volume, forKey: "localMusicVolume")
        }
    }

    func setPlayMode(_ mode: MusicPlayMode) {
        guard playMode != mode else { return }
        playMode = mode
        rebuildBilibiliPlaybackQueue()
        persistLibrary()
    }

    func importLocalMusic(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        localImportTask?.cancel()
        localImportStore.isImporting = true
        localImportStore.message = nil
        localImportStore.errorMessage = nil
        localImportTask = Task(priority: .utility) { [weak self, localMusicImporter] in
            let result = await localMusicImporter.importFiles(urls)
            guard !Task.isCancelled, let self else { return }
            let existingKeys = Set(playlist.compactMap(\.localDuplicateKey))
            var seen = existingKeys
            let added = result.tracks.filter { track in
                guard let key = track.localDuplicateKey else { return true }
                return seen.insert(key).inserted
            }
            let duplicates = result.tracks.count - added.count
            playlist.append(contentsOf: added)
            localImportStore.importedCount = added.count
            localImportStore.duplicateCount = duplicates
            localImportStore.failedCount = result.failures.count
            localImportStore.message = AppLocalizer.format(
                "music.local.import.result",
                added.count,
                duplicates,
                result.failures.count
            )
            localImportStore.isImporting = false
            localImportTask = nil
            if !added.isEmpty {
                setSource(.local)
                if currentTrack?.source != .local { restoreSelection(for: .local) }
                rebuildBilibiliPlaybackQueue()
                persistLibrary()
            }
        }
    }

    func cancelLocalImport() {
        localImportTask?.cancel()
        localImportTask = nil
        localImportStore.isImporting = false
    }

    func relocate(_ track: MusicTrack, to url: URL) {
        Task { [weak self, localMusicImporter] in
            guard let self else { return }
            do {
                let updated = try await localMusicImporter.relocatedTrack(track, to: url)
                guard let index = playlist.firstIndex(where: { $0.id == track.id }) else { return }
                playlist[index] = updated
                if currentTrack?.id == track.id { currentTrack = updated }
                localImportStore.trackNeedingRelocation = nil
                localImportStore.errorMessage = nil
                persistLibrary()
            } catch {
                localImportStore.errorMessage = error.localizedDescription
            }
        }
    }

    func importBilibili() {
        let input = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        dismissBilibiliImportResult()
        Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await bilibili.resolveTracks(from: input)
                var added: [MusicTrack] = []
                for track in tracks where !playlist.contains(where: { $0.id == track.id }) {
                    playlist.append(track); added.append(track)
                }
                if !added.isEmpty { rebuildBilibiliPlaybackQueue() }
                importText = ""
                setSource(.bilibili)
                persistLibrary()
                let importedTrackID = (added.first ?? tracks.first)?.id
                let message = added.isEmpty
                    ? AppLocalizer.string("歌曲已在资料库中")
                    : AppLocalizer.format("music.import.addedCount", added.count)
                showBilibiliImportResult(message, trackID: importedTrackID)
            } catch { errorMessage = error.localizedDescription }
            isImporting = false
        }
    }

    func playLastBilibiliImport() {
        guard let lastImportedTrackID,
              let track = playlist.first(where: { $0.id == lastImportedTrackID }) else {
            dismissBilibiliImportResult()
            return
        }
        dismissBilibiliImportResult()
        play(track)
    }

    func dismissBilibiliImportResult() {
        bilibiliImportResultTask?.cancel()
        bilibiliImportResultTask = nil
        bilibiliImportMessage = nil
        lastImportedTrackID = nil
    }

    private func showBilibiliImportResult(_ message: String, trackID: String?) {
        bilibiliImportResultTask?.cancel()
        bilibiliImportMessage = message
        lastImportedTrackID = trackID
        bilibiliImportResultTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, bilibiliImportMessage == message, lastImportedTrackID == trackID else { return }
            dismissBilibiliImportResult()
        }
    }

    func loadBilibiliFavoriteFolders() {
        guard let account = bilibiliAccount else {
            bilibiliFavoriteMessage = AppLocalizer.string("请先登录哔哩哔哩账号")
            return
        }
        bilibiliFavoriteTask?.cancel()
        isLoadingBilibiliFavoriteFolders = true
        bilibiliFavoriteMessage = nil
        bilibiliFavoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let folders = try await bilibiliFavoritesService.folders(for: account.mid)
                guard !Task.isCancelled else { return }
                bilibiliFavoriteFolders = folders
                if folders.isEmpty {
                    bilibiliFavoriteMessage = AppLocalizer.string("这个账号没有可导入的视频收藏夹")
                }
            } catch is CancellationError {
                return
            } catch {
                bilibiliFavoriteMessage = error.localizedDescription
            }
            isLoadingBilibiliFavoriteFolders = false
            bilibiliFavoriteTask = nil
        }
    }

    func importBilibiliFavoriteFolder(_ folder: BilibiliFavoriteFolder) {
        guard bilibiliAccount != nil, !isImportingBilibiliFavoriteFolder else { return }
        bilibiliFavoriteTask?.cancel()
        isLoadingBilibiliFavoriteFolders = false
        isImportingBilibiliFavoriteFolder = true
        bilibiliFavoriteImportCompleted = 0
        bilibiliFavoriteImportTotal = max(folder.mediaCount, 0)
        bilibiliFavoriteMessage = nil
        bilibiliFavoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bvids = try await bilibiliFavoritesService.videoBVIDs(in: folder)
                guard !bvids.isEmpty else {
                    bilibiliFavoriteMessage = AppLocalizer.format(
                        "music.bilibili.favorite.emptyFolder",
                        folder.title
                    )
                    isImportingBilibiliFavoriteFolder = false
                    bilibiliFavoriteTask = nil
                    return
                }
                bilibiliFavoriteImportTotal = bvids.count
                var resolved: [(Int, [MusicTrack])] = []
                var failedCount = 0
                let batchSize = 4
                let client = bilibili
                for start in stride(from: 0, to: bvids.count, by: batchSize) {
                    try Task.checkCancellation()
                    let end = min(start + batchSize, bvids.count)
                    let batch = Array(bvids[start..<end].enumerated()).map { (start + $0.offset, $0.element) }
                    let batchResults = await withTaskGroup(of: (Int, [MusicTrack]?).self) { group in
                        for (index, bvid) in batch {
                            group.addTask { [client] in
                                do { return (index, try await client.resolveTracks(from: bvid)) }
                                catch { return (index, nil) }
                            }
                        }
                        var values: [(Int, [MusicTrack]?)] = []
                        for await value in group { values.append(value) }
                        return values
                    }
                    for (index, tracks) in batchResults {
                        if let tracks { resolved.append((index, tracks)) }
                        else { failedCount += 1 }
                        bilibiliFavoriteImportCompleted += 1
                    }
                }
                guard !Task.isCancelled else { return }
                let tracks = resolved.sorted { $0.0 < $1.0 }.flatMap(\.1)
                let existingIDs = Set(playlist.map(\.id))
                let added = tracks.filter { !existingIDs.contains($0.id) }
                playlist.append(contentsOf: added)
                if !added.isEmpty { rebuildBilibiliPlaybackQueue() }
                updateLocalPlaylist(named: folder.title, with: tracks)
                setSource(.bilibili)
                persistLibrary()
                let duplicateCount = tracks.count - added.count
                bilibiliFavoriteMessage = AppLocalizer.format(
                    "music.bilibili.favorite.importResult",
                    folder.title,
                    added.count,
                    duplicateCount,
                    failedCount
                )
            } catch is CancellationError {
                return
            } catch {
                bilibiliFavoriteMessage = error.localizedDescription
            }
            isImportingBilibiliFavoriteFolder = false
            bilibiliFavoriteTask = nil
        }
    }

    func cancelBilibiliFavoriteOperation() {
        bilibiliFavoriteTask?.cancel()
        bilibiliFavoriteTask = nil
        isLoadingBilibiliFavoriteFolders = false
        isImportingBilibiliFavoriteFolder = false
    }

    private func updateLocalPlaylist(named name: String, with tracks: [MusicTrack]) {
        guard !tracks.isEmpty else { return }
        if let index = savedPlaylists.firstIndex(where: { $0.name == name }) {
            var existing = Set(savedPlaylists[index].trackIDs)
            savedPlaylists[index].trackIDs.append(contentsOf: tracks.map(\.id).filter { existing.insert($0).inserted })
        } else {
            var seen = Set<String>()
            savedPlaylists.append(SavedMusicPlaylist(
                name: name,
                trackIDs: tracks.map(\.id).filter { seen.insert($0).inserted }
            ))
        }
    }

    func refreshBilibiliAccount() {
        Task { [weak self] in
            guard let self else { return }
            do {
                bilibiliAccount = try await bilibiliAccountService.currentAccount()
                bilibiliLoginPhase = bilibiliAccount == nil ? .loggedOut : .loggedIn
            } catch {
                bilibiliLoginPhase = .failed(error.localizedDescription)
            }
        }
    }

    func startBilibiliLogin() {
        bilibiliLoginTask?.cancel()
        bilibiliLoginPhase = .requestingQRCode
        bilibiliQRCodeURL = nil
        bilibiliLoginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await bilibiliAccountService.generateQRCode()
                guard !Task.isCancelled else { return }
                bilibiliQRCodeURL = code.url
                bilibiliLoginPhase = .waitingForScan
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    switch try await bilibiliAccountService.pollQRCode(key: code.key) {
                    case .waitingForScan:
                        bilibiliLoginPhase = .waitingForScan
                    case .waitingForConfirmation:
                        bilibiliLoginPhase = .waitingForConfirmation
                    case .expired:
                        bilibiliLoginPhase = .expired
                        bilibiliQRCodeURL = nil
                        bilibiliLoginTask = nil
                        return
                    case .succeeded:
                        guard let account = try await bilibiliAccountService.currentAccount() else {
                            throw BilibiliAccountError.api(AppLocalizer.string("登录凭据未生效"))
                        }
                        bilibiliAccount = account
                        bilibiliLoginPhase = .loggedIn
                        bilibiliQRCodeURL = nil
                        bilibiliLoginTask = nil
                        await refreshCurrentBilibiliSubtitleAfterLogin()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                bilibiliLoginPhase = .failed(error.localizedDescription)
                bilibiliQRCodeURL = nil
                bilibiliLoginTask = nil
            }
        }
    }

    func cancelBilibiliLogin() {
        bilibiliLoginTask?.cancel()
        bilibiliLoginTask = nil
        bilibiliQRCodeURL = nil
        if bilibiliAccount == nil { bilibiliLoginPhase = .loggedOut }
    }

    func logoutBilibili() {
        bilibiliLoginTask?.cancel()
        bilibiliLoginTask = nil
        Task { [weak self] in
            guard let self else { return }
            await bilibiliAccountService.logout()
            bilibiliAccount = nil
            bilibiliQRCodeURL = nil
            bilibiliLoginPhase = .loggedOut
            bilibiliFavoriteFolders = []
            bilibiliFavoriteMessage = nil
        }
    }

    func play(_ track: MusicTrack, at savedPosition: TimeInterval = 0) {
        registerManualPlaybackControl()
        switch track.source {
        case .local:
            playLocalTrack(track, at: savedPosition, rebuildQueue: true)
        case .bilibili:
            playBilibiliTrack(track, at: savedPosition, rebuildQueue: true)
        case .appleMusic:
            connectAppleMusic(autoplay: true)
        }
    }

    func pauseForExternalAudio() {
        guard isPlaying else { return }
        pausedForExternalAudio = true
        switch playbackSource {
        case .appleMusic:
            lastAppleClockTime = nil
            setPlaybackState(.paused)
            Task { [appleMusic] in await appleMusic.pause() }
        case .bilibili:
            bilibiliPlayer?.pause()
        case .local:
            bilibiliPlayer?.pause()
        }
    }

    func resumeAfterExternalAudio() {
        guard pausedForExternalAudio else { return }
        pausedForExternalAudio = false
        switch playbackSource {
        case .appleMusic:
            guard appleMusicRunning else { return }
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            setPlaybackState(.playing)
            Task { [weak self, appleMusic] in
                await appleMusic.play()
                self?.scheduleAppleRefresh()
            }
        case .bilibili:
            guard let bilibiliPlayer, bilibiliPlayer.hasLoadedItem else { return }
            bilibiliPlayer.play()
        case .local:
            guard let bilibiliPlayer, bilibiliPlayer.hasLoadedItem else { return }
            bilibiliPlayer.play()
        }
    }

    func cancelExternalAudioResume() {
        let hadAutomaticPause = pausedForExternalAudio
        pausedForExternalAudio = false
        if hadAutomaticPause { onExternalAudioResumeCancelled?() }
    }

    private func registerManualPlaybackControl() {
        cancelExternalAudioResume()
        onExternalAudioManualControl?()
    }

    private func playBilibiliTrack(
        _ track: MusicTrack,
        at savedPosition: TimeInterval = 0,
        rebuildQueue: Bool
    ) {
        guard track.source == .bilibili else { return }
        activatePlaybackSource(.bilibili)
        _ = ensureBilibiliPlayer()
        currentTrack = track
        currentTrackID = track.id
        if rebuildQueue { rebuildBilibiliPlaybackQueue() }
        lastBilibiliPosition = savedPosition
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        setPlaybackState(.loading)
        errorMessage = nil
        bilibiliRefreshAttempted = false
        loadLyrics(for: track)
        loadBilibiliTrack(track, position: savedPosition)
    }

    private func playLocalTrack(
        _ track: MusicTrack,
        at savedPosition: TimeInterval = 0,
        rebuildQueue: Bool
    ) {
        guard track.source == .local else { return }
        activatePlaybackSource(.local)
        let player = ensureBilibiliPlayer()
        player.setVolume(localVolume)
        currentTrack = track
        currentTrackID = track.id
        if rebuildQueue { rebuildBilibiliPlaybackQueue() }
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        setPlaybackState(.loading)
        localImportStore.errorMessage = nil
        localImportStore.trackNeedingRelocation = nil
        loadLyrics(for: track)
        localLoadTask?.cancel()
        localLoadTask = Task { [weak self, localMusicImporter] in
            guard let self else { return }
            do {
                let url = try await localMusicImporter.resolveURL(for: track)
                guard !Task.isCancelled,
                      activePlaybackSource == .local,
                      currentTrack?.id == track.id else { return }
                releaseScopedLocalURL()
                _ = url.startAccessingSecurityScopedResource()
                scopedLocalURL = url
                player.load(urls: [url], headers: [:], position: savedPosition, autoplay: true)
                persistLibrary()
            } catch {
                guard !Task.isCancelled else { return }
                setPlaybackState(.failed(error.localizedDescription))
                localImportStore.errorMessage = error.localizedDescription
                if error as? LocalMusicImportError == .staleBookmark
                    || error as? LocalMusicImportError == .missingFile {
                    localImportStore.trackNeedingRelocation = track
                }
            }
            localLoadTask = nil
        }
    }

    private func releaseScopedLocalURL() {
        scopedLocalURL?.stopAccessingSecurityScopedResource()
        scopedLocalURL = nil
    }

    private func loadBilibiliTrack(_ track: MusicTrack, position savedPosition: TimeInterval) {
        bilibiliLoadTask?.cancel()
        bilibiliLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let location = try await bilibili.audioLocation(for: track)
                let headers = await bilibili.playbackHeaders()
                guard !Task.isCancelled,
                      activePlaybackSource == .bilibili,
                      currentTrack?.id == track.id else { return }
                guard let bilibiliPlayer else { return }
                bilibiliPlayer.load(
                    urls: location.candidates,
                    headers: headers,
                    position: savedPosition,
                    autoplay: true
                )
                persistLibrary()
            } catch {
                guard !Task.isCancelled, activePlaybackSource == .bilibili else { return }
                setPlaybackState(.failed(error.localizedDescription))
                errorMessage = error.localizedDescription
            }
            bilibiliLoadTask = nil
        }
    }

    func remove(_ track: MusicTrack) {
        let wasCurrent = currentTrack?.id == track.id
        let removedSource = track.source
        playlist.removeAll { $0.id == track.id }
        favoriteTrackIDs.remove(track.id)
        removeCachedLyrics(for: track)
        for index in savedPlaylists.indices { savedPlaylists[index].trackIDs.removeAll { $0 == track.id } }
        if wasCurrent {
            bilibiliPlayer?.stop(); currentTrack = nil; currentTrackID = nil; setPlaybackState(.stopped)
            releaseScopedLocalURL()
            if removedSource == .bilibili { lastBilibiliPosition = 0 }
            if activePlaybackSource == removedSource {
                activePlaybackSource = nil
                scheduleBilibiliPlayerRelease()
            }
            playbackProgress.reset(); cancelLyricLoad()
            lyrics = nil; currentLyric = nil; nextLyric = nil; currentLyricIndex = nil
        }
        rebuildBilibiliPlaybackQueue()
        persistLibrary()
    }

    func clearPlaylist() {
        let source = browsingSource
        guard source != .appleMusic else { return }
        let removedTracks = playlist.filter { $0.source == source }
        let removedIDs = Set(removedTracks.map(\.id))
        for track in removedTracks { removeCachedLyrics(for: track) }
        playlist.removeAll { $0.source == source }
        favoriteTrackIDs.subtract(removedIDs)
        for index in savedPlaylists.indices {
            savedPlaylists[index].trackIDs.removeAll { removedIDs.contains($0) }
        }
        if currentTrack?.source == source {
            bilibiliPlayer?.stop()
            releaseScopedLocalURL()
            currentTrackID = nil
        }
        if source == .bilibili { lastBilibiliPosition = 0 }
        if activePlaybackSource == source || currentTrack?.source == source {
            activePlaybackSource = nil
            scheduleBilibiliPlayerRelease()
            currentTrack = nil; setPlaybackState(.stopped)
            playbackProgress.reset(); cancelLyricLoad()
            lyrics = nil; currentLyric = nil; nextLyric = nil; currentLyricIndex = nil
        }
        rebuildBilibiliPlaybackQueue()
        persistLibrary()
    }

    func isFavorite(_ track: MusicTrack) -> Bool { favoriteTrackIDs.contains(track.id) }

    func toggleFavorite(_ track: MusicTrack) {
        if favoriteTrackIDs.contains(track.id) { favoriteTrackIDs.remove(track.id) }
        else { favoriteTrackIDs.insert(track.id) }
        persistLibrary()
    }

    @discardableResult
    func createPlaylist(named rawName: String) -> SavedMusicPlaylist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let playlist = SavedMusicPlaylist(name: name)
        savedPlaylists.append(playlist)
        persistLibrary()
        return playlist
    }

    func deletePlaylist(_ savedPlaylist: SavedMusicPlaylist) {
        savedPlaylists.removeAll { $0.id == savedPlaylist.id }
        persistLibrary()
    }

    func add(_ track: MusicTrack, to savedPlaylist: SavedMusicPlaylist) {
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }),
              !savedPlaylists[index].trackIDs.contains(track.id) else { return }
        savedPlaylists[index].trackIDs.append(track.id)
        persistLibrary()
    }

    func remove(_ track: MusicTrack, from savedPlaylist: SavedMusicPlaylist) {
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }) else { return }
        savedPlaylists[index].trackIDs.removeAll { $0 == track.id }
        persistLibrary()
    }

    func tracks(in savedPlaylist: SavedMusicPlaylist) -> [MusicTrack] {
        let byID = Dictionary(uniqueKeysWithValues: playlist.map { ($0.id, $0) })
        return savedPlaylist.trackIDs.compactMap { byID[$0] }
    }

    var favoriteTracks: [MusicTrack] { playlist.filter { favoriteTrackIDs.contains($0.id) } }
    var upcomingTracks: [MusicTrack] {
        let tracksByID = Dictionary(playlist.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        return upcomingTrackIDs.compactMap { tracksByID[$0] }
    }

    func toggleLyricsVisible() {
        lyricsVisible.toggle()
        defaults.set(lyricsVisible, forKey: "musicLyricsVisible")
        lyricsPresentation.onVisibilityChanged?()
    }

    func setLightSingAlongEnabled(_ enabled: Bool) {
        lightSingAlongEnabled = enabled
        defaults.set(enabled, forKey: "musicLightSingAlong")
    }

    func setLyricsPanelLocked(_ locked: Bool) {
        lyricsPanelLocked = locked
        defaults.set(locked, forKey: "musicLyricsPanelLocked")
        lyricsPresentation.onLockChanged?()
    }

    func setLyricsFontSize(_ size: Double) {
        lyricsFontSize = min(max(size, 14), 42)
        defaults.set(lyricsFontSize, forKey: "musicLyricsFontSize")
    }

    func setLyricsFontStyle(_ style: LyricsFontStyle) {
        lyricsFontStyle = style
        defaults.set(style.rawValue, forKey: "musicLyricsFontStyle")
    }

    func setLyricsColor(_ color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return }
        lyricsColor = color
        defaults.set(Self.encodeColor(color), forKey: "musicLyricsColor")
    }

    func setLyricsShadowEnabled(_ enabled: Bool) {
        lyricsShadowEnabled = enabled
        defaults.set(enabled, forKey: "musicLyricsShadowEnabled")
    }

    func setLyricsBackgroundVisible(_ visible: Bool) {
        lyricsBackgroundVisible = visible
        defaults.set(visible, forKey: "musicLyricsBackgroundVisible")
    }

    func setLyricsBackgroundOpacity(_ opacity: Double) {
        lyricsBackgroundOpacity = min(max(opacity, 0.12), 0.60)
        defaults.set(lyricsBackgroundOpacity, forKey: "musicLyricsBackgroundOpacity")
    }

    func setLyricOffset(_ offset: TimeInterval) {
        guard let trackID = currentTrack?.id else { return }
        let clamped = min(max(offset, -30), 30)
        if abs(clamped) < 0.001 { lyricOffsets.removeValue(forKey: trackID) }
        else { lyricOffsets[trackID] = clamped }
        updateLyric()
        persistLibrary()
    }

    func searchLyrics(title rawTitle: String, artist rawArtist: String) {
        guard let track = currentTrack else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            lyricsSearchMessage = AppLocalizer.string("请填写歌曲名")
            return
        }
        isSearchingLyrics = true
        lyricsSearchMessage = nil
        cancelLyricLoad()
        lyricsSearchTask?.cancel()
        lyricsSearchTask = Task { [weak self] in
            guard let self else { return }
            let found: LyricsDocument?
            do {
                found = try await lyricsService.search(title: title, artist: artist, duration: track.duration)
            } catch is CancellationError {
                return
            } catch {
                guard currentTrack?.id == track.id else { return }
                lyricsSearchMessage = error.localizedDescription
                isSearchingLyrics = false
                lyricsSearchTask = nil
                return
            }
            guard !Task.isCancelled, currentTrack?.id == track.id else { return }
            if let found {
                lyrics = found
                cacheLyrics(found, for: track)
                updateMetadata(for: track.id, title: title, artist: artist)
                updateLyric()
                persistLibrary()
                lyricsSearchMessage = AppLocalizer.format(
                    "music.lyrics.matchResult",
                    title,
                    artist.isEmpty ? AppLocalizer.string("未知歌手") : artist
                )
            } else {
                lyricsSearchMessage = AppLocalizer.string("没有找到可信度足够的同步歌词，已保留原有歌词")
            }
            isSearchingLyrics = false
            lyricsSearchTask = nil
        }
    }

    @discardableResult
    func updateCurrentTrackMetadata(title rawTitle: String, artist rawArtist: String) -> Bool {
        guard let track = currentTrack else { return false }
        let enteredTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredArtist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = enteredTitle.isEmpty ? track.title : enteredTitle
        let artist = enteredArtist.isEmpty ? track.artist : enteredArtist
        guard !title.isEmpty, !artist.isEmpty else {
            lyricsSearchMessage = AppLocalizer.string("歌曲名和歌手不能同时留空")
            return false
        }
        updateMetadata(for: track.id, title: title, artist: artist)
        lyricsSearchMessage = AppLocalizer.format("music.lyrics.metadataSaved", title, artist)
        return true
    }

    private func updateMetadata(for trackID: String, title: String, artist: String) {
        let resolvedArtist = artist.isEmpty
            ? (currentTrack?.artist ?? AppLocalizer.string("未知歌手"))
            : artist
        if let index = playlist.firstIndex(where: { $0.id == trackID }) {
            playlist[index].title = title
            playlist[index].artist = resolvedArtist
            currentTrack = playlist[index]
            persistLibrary()
        } else if currentTrack?.id == trackID {
            currentTrack?.title = title
            currentTrack?.artist = resolvedArtist
        }
    }

    private static func encodeColor(_ color: NSColor) -> String {
        let color = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255)),
            Int(round(color.alphaComponent * 255))
        )
    }

    static func decodeLyricsColor(_ value: String?) -> NSColor? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 || hex.count == 8, let raw = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        return NSColor(
            red: CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
            green: CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
            blue: CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
            alpha: hasAlpha ? CGFloat(raw & 0xFF) / 255 : 1
        )
    }

    func importLRC(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            errorMessage = AppLocalizer.string("无法读取这个 LRC 文件"); return
        }
        cancelLyricLoad()
        let document = LyricsParser.parseLRC(text)
        lyrics = document
        if let track = currentTrack {
            cacheLyrics(document, for: track)
            persistLibrary()
        }
        updateLyric()
    }

    func shutdown() async {
        cancelExternalAudioResume()
        libraryRestoreTask?.cancel()
        stopAppleSyncTask()
        stopAppleClock()
        bilibiliPlayerReleaseTask?.cancel()
        bilibiliPlayerReleaseTask = nil
        appleRefreshTask?.cancel(); appleArtworkTask?.cancel(); bilibiliImportResultTask?.cancel()
        lyricLoadTask?.cancel(); lyricsSearchTask?.cancel(); bilibiliLoadTask?.cancel(); bilibiliLoginTask?.cancel(); bilibiliFavoriteTask?.cancel()
        localImportTask?.cancel(); localLoadTask?.cancel()
        unloadBilibiliPlayer()
        appleMusicWorkspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appleMusicWorkspaceObservers.removeAll()
        persistenceRevision &+= 1
        await library.saveNow(librarySnapshot(), revision: persistenceRevision)
    }

    private func refreshAppleMusic() async {
        guard activePlaybackSource == .appleMusic else { return }
        let performanceStart = RuntimePerformance.start()
        defer { RuntimePerformance.record("music.apple.sync", since: performanceStart) }
        let running = await appleMusic.isRunning()
        if appleMusicRunning != running { appleMusicRunning = running }
        guard appleMusicRunning else {
            stopAppleSyncTask()
            if activePlaybackSource == .appleMusic { setPlaybackState(.stopped) }
            return
        }
        do {
            let snapshot = try await appleMusic.requestSnapshot()
            guard activePlaybackSource == .appleMusic else { return }
            let changed = currentTrack?.id != snapshot.track?.id
            var publishedTrack = snapshot.track
            if publishedTrack?.id == currentTrack?.id, publishedTrack?.coverURL == nil {
                publishedTrack?.coverURL = currentTrack?.coverURL
            }
            if currentTrack != publishedTrack { currentTrack = publishedTrack }
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            if playbackState != snapshot.state { setPlaybackState(snapshot.state) }
            playbackProgress.reset(position: snapshot.position, duration: snapshot.track?.duration ?? 0)
            if volume != snapshot.volume { volume = snapshot.volume }
            if changed, let track = publishedTrack {
                loadLyrics(for: track)
                loadAppleArtwork(for: track)
            }
            updateLyric()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func startAppleSyncTask() {
        guard activePlaybackSource == .appleMusic,
              appleMusicRunning,
              appleSyncTask == nil else { return }
        appleSyncGeneration &+= 1
        let generation = appleSyncGeneration
        appleSyncTask = Task { [weak self] in
            await self?.runAppleSyncLoop(generation: generation)
        }
    }

    private func stopAppleSyncTask() {
        appleSyncGeneration &+= 1
        appleSyncTask?.cancel()
        appleSyncTask = nil
    }

    private func finishAppleSyncTask(generation: UInt) {
        guard appleSyncGeneration == generation else { return }
        appleSyncTask = nil
    }

    private func runAppleSyncLoop(generation: UInt) async {
        defer { finishAppleSyncTask(generation: generation) }
        while !Task.isCancelled {
            guard activePlaybackSource == .appleMusic, appleMusicRunning else { return }
            await refreshAppleMusic()
            do { try await Task.sleep(for: .milliseconds(2_500)) } catch { return }
        }
    }

    private func installAppleMusicWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self,
                          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication,
                          application.bundleIdentifier == "com.apple.Music" else { return }
                    let isRunning = name == NSWorkspace.didLaunchApplicationNotification
                    self.appleMusicRunning = isRunning
                    if isRunning {
                        self.startAppleSyncTask()
                        self.scheduleAppleRefresh()
                    } else if self.activePlaybackSource == .appleMusic {
                        self.stopAppleSyncTask()
                        self.stopAppleClock()
                        self.setPlaybackState(.stopped)
                    }
                }
            }
            appleMusicWorkspaceObservers.append(observer)
        }
    }

    private func startAppleClockIfNeeded() {
        guard activePlaybackSource == .appleMusic,
              playbackState.isPlaying,
              appleClockTask == nil else { return }
        appleClockGeneration &+= 1
        let generation = appleClockGeneration
        appleClockTask = Task { [weak self] in
            await self?.runAppleClock(generation: generation)
        }
    }

    private func stopAppleClock() {
        appleClockGeneration &+= 1
        appleClockTask?.cancel()
        appleClockTask = nil
        lastAppleClockTime = nil
    }

    private func finishAppleClockTask(generation: UInt) {
        guard appleClockGeneration == generation else { return }
        appleClockTask = nil
        lastAppleClockTime = nil
    }

    private func runAppleClock(generation: UInt) async {
        defer { finishAppleClockTask(generation: generation) }
        while !Task.isCancelled {
            guard activePlaybackSource == .appleMusic, playbackState.isPlaying else { return }
            let now = Date.timeIntervalSinceReferenceDate
            if let lastAppleClockTime {
                let elapsed = min(max(now - lastAppleClockTime, 0), 1)
                let advanced = duration > 0 ? min(position + elapsed, duration) : position + elapsed
                playbackProgress.setPosition(advanced)
                updateLyric()
            }
            lastAppleClockTime = now
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }

    private func loadAppleArtwork(for track: MusicTrack) {
        appleArtworkTask?.cancel()
        appleArtworkTask = Task { [weak self, appleMusic] in
            let url = await appleMusic.artworkURL(for: track.id)
            guard !Task.isCancelled, let self, currentTrack?.id == track.id else { return }
            if currentTrack?.coverURL != url { currentTrack?.coverURL = url }
            appleArtworkTask = nil
        }
    }

    private func scheduleAppleRefresh() {
        appleRefreshTask?.cancel()
        appleRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await self?.refreshAppleMusic()
        }
    }

    private func move(by delta: Int) {
        let controlSource = activePlaybackSource ?? currentTrack?.source ?? browsingSource
        if controlSource == .appleMusic {
            if activePlaybackSource == nil { connectAppleMusic() }
            Task { [weak self, appleMusic] in
                if delta < 0 { await appleMusic.previous() } else { await appleMusic.next() }
                self?.scheduleAppleRefresh()
            }
            return
        }
        let sourcePlaylist = playlist.filter { $0.source == controlSource }
        guard !sourcePlaylist.isEmpty else { return }
        let targetID = delta < 0
            ? bilibiliPlaybackQueue.previousTrackID(
                playlist: sourcePlaylist, currentTrackID: currentTrack?.id, mode: playMode
            )
            : bilibiliPlaybackQueue.nextTrackID(
                playlist: sourcePlaylist, currentTrackID: currentTrack?.id, mode: playMode
            )
        publishUpcomingTracks()
        guard let targetID, let track = sourcePlaylist.first(where: { $0.id == targetID }) else { return }
        if track.source == .local {
            playLocalTrack(track, rebuildQueue: false)
        } else {
            playBilibiliTrack(track, rebuildQueue: false)
        }
    }

    private func handleTrackFinished() {
        guard activePlaybackSource == .bilibili || activePlaybackSource == .local else { return }
        guard !(blocksAutomaticPlaybackForExternalAudio?() ?? false) else {
            setPlaybackState(.paused)
            return
        }
        if playMode == .repeatOne, let currentTrack { play(currentTrack) }
        else { move(by: 1) }
    }

    private func handleURLPlayerFailure(_ error: Error) {
        if activePlaybackSource == .local {
            setPlaybackState(.failed(error.localizedDescription))
            localImportStore.errorMessage = error.localizedDescription
            return
        }
        guard activePlaybackSource == .bilibili, let track = currentTrack else { return }
        if !bilibiliRefreshAttempted {
            bilibiliRefreshAttempted = true
            setPlaybackState(.loading)
            loadBilibiliTrack(track, position: position)
        } else {
            let failure = AppLocalizer.string("播放地址已失效，刷新后仍无法播放")
            setPlaybackState(.failed(failure))
            errorMessage = AppLocalizer.format(
                "music.bilibili.playbackExpiredDetail",
                error.localizedDescription
            )
        }
    }

    private func loadLyrics(for track: MusicTrack) {
        let performanceStart = RuntimePerformance.start()
        defer { RuntimePerformance.record("music.lyrics.schedule", since: performanceStart) }
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
        cancelLyricLoad()
        let revision = lyricLoadRevision
        isSearchingLyrics = false
        lyricsSearchMessage = nil
        if track.source == .appleMusic, let cached = cachedLyrics(for: track) {
            lyrics = cached
            updateLyric()
            return
        }
        lyrics = nil
        updateLyric()
        isLoadingLyrics = true
        lyricLoadTask = Task { [weak self] in
            let loadPerformanceStart = RuntimePerformance.start()
            defer { RuntimePerformance.record("music.lyrics.load", since: loadPerformanceStart) }
            guard let self else { return }
            var resolvedTrack = track
            var cached = cachedLyrics(for: track)
            if track.source == .local {
                if let local = try? await localMusicImporter.localLyrics(for: track), !local.lines.isEmpty {
                    guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
                    lyrics = local
                    cacheLyrics(local, for: track)
                    persistLibrary()
                    updateLyric()
                    finishLyricLoad(revision, trackID: track.id)
                    return
                }
                if let cached {
                    guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
                    lyrics = cached
                    updateLyric()
                    finishLyricLoad(revision, trackID: track.id)
                    return
                }
            }
            if track.source == .bilibili {
                let exactSubtitleURL = await bilibili.subtitleURL(for: track)
                guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
                if let exactSubtitleURL {
                    resolvedTrack.subtitleURL = exactSubtitleURL
                    if exactSubtitleURL != track.subtitleURL {
                        updateSubtitleURL(exactSubtitleURL, for: track.id)
                        if cached?.source == "Bilibili 字幕" {
                            removeCachedLyrics(for: track)
                            cached = nil
                        }
                    }
                    if cached?.source == "LRCLIB" {
                        removeCachedLyrics(for: track)
                        cached = nil
                    }
                }
            }
            if let cached {
                guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
                lyrics = cached
                updateLyric()
                finishLyricLoad(revision, trackID: track.id)
                return
            }
            let found = await lyricsService.lyrics(for: resolvedTrack)
            guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
            lyrics = found
            if let found {
                cacheLyrics(found, for: track)
                persistLibrary()
            }
            updateLyric()
            finishLyricLoad(revision, trackID: track.id)
        }
    }

    private func cancelLyricLoad() {
        lyricLoadRevision &+= 1
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        if isLoadingLyrics { isLoadingLyrics = false }
    }

    private func isCurrentLyricLoad(_ revision: UInt64, trackID: String) -> Bool {
        !Task.isCancelled && lyricLoadRevision == revision && currentTrack?.id == trackID
    }

    private func finishLyricLoad(_ revision: UInt64, trackID: String) {
        guard lyricLoadRevision == revision, currentTrack?.id == trackID else { return }
        if isLoadingLyrics { isLoadingLyrics = false }
        lyricLoadTask = nil
    }

    private func refreshCurrentBilibiliSubtitleAfterLogin() async {
        guard let track = currentTrack, track.source == .bilibili,
              let subtitleURL = await bilibili.subtitleURL(for: track) else { return }
        updateSubtitleURL(subtitleURL, for: track.id)
        if cachedLyrics(for: track)?.source == "LRCLIB" {
            removeCachedLyrics(for: track)
        }
        loadLyrics(for: currentTrack ?? track)
    }

    private func updateSubtitleURL(_ url: URL, for trackID: String) {
        if let index = playlist.firstIndex(where: { $0.id == trackID }) {
            playlist[index].subtitleURL = url
            if currentTrack?.id == trackID { currentTrack = playlist[index] }
        } else if currentTrack?.id == trackID {
            currentTrack?.subtitleURL = url
        }
        persistLibrary()
    }

    private func cachedLyrics(for track: MusicTrack) -> LyricsDocument? {
        if let cached = lyricsByTrackID[track.lyricsCacheKey] ?? lyricsByTrackID[track.id] {
            return cached
        }
        guard track.source == .appleMusic,
              let legacy = lyricsByTrackID.first(where: { track.matchesLegacyLyricsCacheKey($0.key) }) else {
            return nil
        }
        lyricsByTrackID[track.lyricsCacheKey] = legacy.value
        lyricsByTrackID.removeValue(forKey: legacy.key)
        persistLibrary()
        return legacy.value
    }

    private func cacheLyrics(_ document: LyricsDocument, for track: MusicTrack) {
        lyricsByTrackID[track.lyricsCacheKey] = document
        if track.lyricsCacheKey != track.id {
            lyricsByTrackID.removeValue(forKey: track.id)
        }
    }

    private func removeCachedLyrics(for track: MusicTrack) {
        lyricsByTrackID.removeValue(forKey: track.lyricsCacheKey)
        lyricsByTrackID.removeValue(forKey: track.id)
        if track.source == .appleMusic {
            lyricsByTrackID.keys
                .filter { track.matchesLegacyLyricsCacheKey($0) }
                .forEach { lyricsByTrackID.removeValue(forKey: $0) }
        }
    }

    private func updateLyric() {
        let adjustedPosition = max(0, position - currentLyricOffset)
        let index = lyrics?.lineIndex(at: adjustedPosition)
        let current = index.flatMap { lyrics?.lines[$0] }
        let nextIndex = index.map { $0 + 1 } ?? 0
        let next = lyrics.flatMap { document in
            document.lines.indices.contains(nextIndex) ? document.lines[nextIndex] : nil
        }
        if currentLyricIndex != index { currentLyricIndex = index }
        if currentLyric != current { currentLyric = current }
        if nextLyric != next { nextLyric = next }
    }

    private func restoreLibrary() async {
        let revisionBeforeLoad = persistenceRevision
        guard let snapshot = try? await library.load() else { return }
        guard persistenceRevision == revisionBeforeLoad else { return }
        playlist = snapshot.playlist
        playMode = snapshot.playMode
        favoriteTrackIDs = snapshot.favoriteTrackIDs
        savedPlaylists = snapshot.savedPlaylists
        lyricOffsets = snapshot.lyricOffsets
        lyricsByTrackID = snapshot.lyricsByTrackID
        currentTrackID = snapshot.currentTrackID
        rebuildBilibiliPlaybackQueue()
        lastBilibiliPosition = snapshot.lastPosition
        if browsingSource == .bilibili || browsingSource == .local {
            restoreSelection(for: browsingSource, position: snapshot.lastPosition)
        }
        else if let currentTrack { loadLyrics(for: currentTrack) }
    }

    private func restoreBilibiliSelection(position savedPosition: TimeInterval = 0) {
        restoreSelection(for: .bilibili, position: savedPosition)
    }

    private func restoreSelection(for source: MusicSource, position savedPosition: TimeInterval = 0) {
        let sourceTracks = playlist.filter { $0.source == source }
        if let id = currentTrackID, let track = sourceTracks.first(where: { $0.id == id }) {
            let restoredPosition = min(max(savedPosition, 0), max(track.duration, 0))
            if source == .bilibili { lastBilibiliPosition = restoredPosition }
            currentTrack = track; playbackProgress.reset(position: restoredPosition, duration: track.duration); setPlaybackState(.paused)
            loadLyrics(for: track)
        } else if let first = sourceTracks.first {
            if source == .bilibili { lastBilibiliPosition = 0 }
            currentTrack = first; currentTrackID = first.id; playbackProgress.reset(position: 0, duration: first.duration); setPlaybackState(.paused)
            loadLyrics(for: first)
        } else {
            currentTrack = nil
            if source == .bilibili { lastBilibiliPosition = 0 }
            playbackProgress.reset()
            setPlaybackState(.stopped)
        }
    }

    private func persistProgressIfNeeded() {
        let second = Int(position)
        guard second != lastSavedSecond, second % 15 == 0 else { return }
        lastSavedSecond = second; persistLibrary()
    }

    private func persistLibrary() {
        persistenceRevision &+= 1
        let revision = persistenceRevision
        let snapshot = librarySnapshot()
        Task { await library.scheduleSave(snapshot, revision: revision) }
    }

    private func rebuildBilibiliPlaybackQueue() {
        bilibiliPlaybackQueue.rebuild(
            playlist: playlist.filter { $0.source == (currentTrack?.source ?? browsingSource) },
            currentTrackID: currentTrackID,
            mode: playMode
        )
        publishUpcomingTracks()
    }

    private func publishUpcomingTracks() {
        let ids = bilibiliPlaybackQueue.upcomingTrackIDs
        if upcomingTrackIDs != ids { upcomingTrackIDs = ids }
    }

    private func librarySnapshot() -> MusicLibrarySnapshot {
        MusicLibrarySnapshot(
            playlist: playlist,
            playMode: playMode,
            currentTrackID: currentTrackID,
            lastPosition: activePlaybackSource == .bilibili || activePlaybackSource == .local
                ? position
                : lastBilibiliPosition,
            favoriteTrackIDs: favoriteTrackIDs,
            savedPlaylists: savedPlaylists,
            lyricOffsets: lyricOffsets,
            lyricsByTrackID: lyricsByTrackID
        )
    }
}
