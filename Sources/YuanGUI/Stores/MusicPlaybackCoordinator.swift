import AppKit
import Foundation

typealias URLMusicPlayerFactory = @MainActor () -> any URLMusicPlaying

@MainActor
protocol MusicPlaybackCoordinatorDelegate: AnyObject {
    var playbackPlaylist: [MusicTrack] { get }
    var playbackCurrentLyricOffset: TimeInterval { get }

    func resetPlaybackLyrics()
    func loadPlaybackLyrics(for track: MusicTrack)
    func updatePlaybackLyric()
    func persistPlaybackLibrary()
    func persistPlaybackProgressIfNeeded()
    func reportBilibiliPlaybackError(_ message: String?)
    func reportLocalPlaybackError(_ message: String?, relocating track: MusicTrack?)
}

@MainActor
final class MusicPlaybackCoordinator {
    weak var delegate: (any MusicPlaybackCoordinatorDelegate)?

    let playback: MusicPlaybackStore
    let defaults: UserDefaults
    let appleMusic: any AppleMusicProviding
    let bilibili: any BilibiliMusicProviding
    let localMusicImporter: any LocalMusicImporting
    let makeURLMusicPlayer: URLMusicPlayerFactory
    let urlPlayerReleaseDelay: Duration
    let tasks = MusicTaskRegistry()

    var urlPlayer: (any URLMusicPlaying)?
    var urlPlayerReleaseTask: Task<Void, Never>?
    var appleSyncTask: Task<Void, Never>?
    var appleClockTask: Task<Void, Never>?
    var appleSyncGeneration: UInt = 0
    var appleClockGeneration: UInt = 0
    var appleRefreshTask: Task<Void, Never>?
    var appleArtworkTask: Task<Void, Never>?
    var bilibiliLoadTask: Task<Void, Never>?
    var localLoadTask: Task<Void, Never>?
    var currentTrackID: String?
    var lastBilibiliPosition: TimeInterval = 0
    var bilibiliRefreshAttempted = false
    var bilibiliVolume: Double
    var localVolume: Double
    var lastAppleClockTime: TimeInterval?
    var musicPlaybackQueue = MusicPlaybackQueue()
    var appleMusicWorkspaceObservers: [NSObjectProtocol] = []
    var pausedForExternalAudio = false
    var scopedLocalURL: URL?
    var loadedURLTrackID: String?
    var loadedURLSource: MusicSource?
    var onExternalAudioResumeCancelled: (() -> Void)?
    var onExternalAudioManualControl: (() -> Void)?
    var blocksAutomaticPlaybackForExternalAudio: (() -> Bool)?

    init(
        playback: MusicPlaybackStore,
        defaults: UserDefaults,
        appleMusic: any AppleMusicProviding,
        bilibili: any BilibiliMusicProviding,
        localMusicImporter: any LocalMusicImporting,
        urlPlayer: (any URLMusicPlaying)?,
        urlPlayerFactory: @escaping URLMusicPlayerFactory,
        urlPlayerReleaseDelay: Duration
    ) {
        self.playback = playback
        self.defaults = defaults
        self.appleMusic = appleMusic
        self.bilibili = bilibili
        self.localMusicImporter = localMusicImporter
        self.urlPlayer = urlPlayer
        makeURLMusicPlayer = urlPlayerFactory
        self.urlPlayerReleaseDelay = urlPlayerReleaseDelay
        bilibiliVolume = defaults.object(forKey: "bilibiliMusicVolume") as? Double ?? 0.8
        localVolume = defaults.object(forKey: "localMusicVolume") as? Double ?? 0.8
    }

    func start() {
        if let urlPlayer {
            configureURLMusicPlayer(urlPlayer)
        }
        installAppleMusicWorkspaceObservers()
    }

    func shutdown() async {
        cancelExternalAudioResume()
        let ownedTasks = [
            urlPlayerReleaseTask,
            appleSyncTask,
            appleClockTask,
            appleRefreshTask,
            appleArtworkTask,
            bilibiliLoadTask,
            localLoadTask
        ].compactMap { $0 }
        ownedTasks.forEach { $0.cancel() }
        await tasks.shutdown()
        for task in ownedTasks {
            await task.value
        }
        urlPlayerReleaseTask = nil
        appleSyncTask = nil
        appleClockTask = nil
        appleRefreshTask = nil
        appleArtworkTask = nil
        bilibiliLoadTask = nil
        localLoadTask = nil
        appleSyncGeneration &+= 1
        appleClockGeneration &+= 1
        lastAppleClockTime = nil
        unloadURLMusicPlayer()
        appleMusicWorkspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appleMusicWorkspaceObservers.removeAll()
    }

    func configureURLMusicPlayer(_ player: any URLMusicPlaying) {
        player.setVolume(bilibiliVolume)
        player.onStateChange = { [weak self] state in
            guard let self,
                  !self.isShuttingDown,
                  self.activePlaybackSource == .bilibili || self.activePlaybackSource == .local else {
                return
            }
            if self.playbackState != state {
                self.setPlaybackState(state)
            }
        }
        player.onProgress = { [weak self] position, duration in
            guard let self,
                  !self.isShuttingDown,
                  self.activePlaybackSource == .bilibili || self.activePlaybackSource == .local else {
                return
            }
            self.playbackProgress.setPosition(position)
            if self.activePlaybackSource == .bilibili {
                self.lastBilibiliPosition = position
            }
            if duration > 0 {
                self.playbackProgress.setDuration(duration)
            }
            self.delegate?.updatePlaybackLyric()
            self.delegate?.persistPlaybackProgressIfNeeded()
        }
        player.onFinished = { [weak self] in self?.handleTrackFinished() }
        player.onFailure = { [weak self] error in self?.handleURLPlayerFailure(error) }
    }

    func ensureURLMusicPlayer() -> any URLMusicPlaying {
        urlPlayerReleaseTask?.cancel()
        urlPlayerReleaseTask = nil
        if let urlPlayer {
            return urlPlayer
        }
        let player = makeURLMusicPlayer()
        configureURLMusicPlayer(player)
        urlPlayer = player
        return player
    }

    func unloadURLMusicPlayer() {
        releaseScopedLocalURL()
        urlPlayer?.onStateChange = nil
        urlPlayer?.onProgress = nil
        urlPlayer?.onFinished = nil
        urlPlayer?.onFailure = nil
        urlPlayer?.stop()
        clearLoadedURLIdentity()
        urlPlayer = nil
    }

    func scheduleURLMusicPlayerRelease() {
        guard !isShuttingDown, urlPlayer != nil else { return }
        urlPlayerReleaseTask?.cancel()
        let releaseDelay = urlPlayerReleaseDelay
        urlPlayerReleaseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: releaseDelay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.urlPlayerReleaseTask = nil
            guard self.activePlaybackSource != .bilibili else { return }
            self.unloadURLMusicPlayer()
        }
    }

    func setPlaybackState(_ state: MusicPlaybackState) {
        guard !isShuttingDown else { return }
        playbackState = state
        guard activePlaybackSource == .appleMusic else { return }
        if state.isPlaying {
            startAppleClockIfNeeded()
        } else {
            stopAppleClock()
        }
    }

    func releaseScopedLocalURL() {
        scopedLocalURL?.stopAccessingSecurityScopedResource()
        scopedLocalURL = nil
    }

    func clearLoadedURLIdentity() {
        loadedURLTrackID = nil
        loadedURLSource = nil
    }

    func hasLoadedCurrentURLTrack(_ track: MusicTrack) -> Bool {
        urlPlayer?.hasLoadedItem == true
            && loadedURLTrackID == track.id
            && loadedURLSource == track.source
    }

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
    var playlist: [MusicTrack] { delegate?.playbackPlaylist ?? [] }
    var position: TimeInterval { playbackProgress.position }
    var duration: TimeInterval { playbackProgress.duration }
    var playbackSource: MusicSource {
        activePlaybackSource ?? currentTrack?.source ?? browsingSource
    }
    var isPlaying: Bool { playbackState.isPlaying }
    var currentLyricOffset: TimeInterval {
        delegate?.playbackCurrentLyricOffset ?? 0
    }
    var isShuttingDown: Bool { tasks.isShuttingDown }
}

extension MusicPlaybackCoordinator: MusicLibraryPlaybackAccess {
    var libraryBrowsingSource: MusicSource { browsingSource }
    var libraryActivePlaybackSource: MusicSource? { activePlaybackSource }
    var libraryCurrentTrack: MusicTrack? { currentTrack }
    var libraryCurrentTrackID: String? {
        get { currentTrackID }
        set { currentTrackID = newValue }
    }
    var libraryLastBilibiliPosition: TimeInterval {
        get { lastBilibiliPosition }
        set { lastBilibiliPosition = newValue }
    }
    var libraryPlaybackPosition: TimeInterval { position }
    var libraryPlayMode: MusicPlayMode {
        get { playMode }
        set { playMode = newValue }
    }
    var libraryUpcomingTrackIDs: [String] { upcomingTrackIDs }

    func removeTrackFromPlayback(_ track: MusicTrack) {
        guard currentTrack?.id == track.id else { return }
        urlPlayer?.stop()
        clearLoadedURLIdentity()
        currentTrack = nil
        currentTrackID = nil
        setPlaybackState(.stopped)
        releaseScopedLocalURL()
        if track.source == .bilibili {
            lastBilibiliPosition = 0
        }
        if activePlaybackSource == track.source {
            activePlaybackSource = nil
            scheduleURLMusicPlayerRelease()
        }
        playbackProgress.reset()
    }

    func clearPlayback(for source: MusicSource) {
        guard activePlaybackSource == source || currentTrack?.source == source else {
            return
        }
        urlPlayer?.stop()
        clearLoadedURLIdentity()
        releaseScopedLocalURL()
        currentTrackID = nil
        if source == .bilibili {
            lastBilibiliPosition = 0
        }
        activePlaybackSource = nil
        scheduleURLMusicPlayerRelease()
        currentTrack = nil
        setPlaybackState(.stopped)
        playbackProgress.reset()
    }

    func rebuildLibraryPlaybackQueue() {
        rebuildMusicPlaybackQueue()
    }

    func restoreLibrarySelection(for source: MusicSource, position: TimeInterval) {
        restoreSelection(for: source, position: position)
    }

    func refreshCurrentPlaybackTrack(_ track: MusicTrack) {
        guard currentTrack?.id == track.id else { return }
        currentTrack = track
    }
}
