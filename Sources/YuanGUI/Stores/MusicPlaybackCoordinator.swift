import AppKit
import Foundation

typealias URLMusicPlayerFactory = @MainActor () -> any URLMusicPlaying

@MainActor
final class MusicPlaybackCoordinator: MusicDomainCoordinator {
    let appleMusic: any AppleMusicProviding
    let bilibili: any BilibiliMusicProviding
    let localMusicImporter: any LocalMusicImporting
    let makeURLMusicPlayer: URLMusicPlayerFactory
    let urlPlayerReleaseDelay: Duration

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
        context: MusicFeatureContext,
        appleMusic: any AppleMusicProviding,
        bilibili: any BilibiliMusicProviding,
        localMusicImporter: any LocalMusicImporting,
        urlPlayer: (any URLMusicPlaying)?,
        urlPlayerFactory: @escaping URLMusicPlayerFactory,
        urlPlayerReleaseDelay: Duration
    ) {
        self.appleMusic = appleMusic
        self.bilibili = bilibili
        self.localMusicImporter = localMusicImporter
        self.urlPlayer = urlPlayer
        makeURLMusicPlayer = urlPlayerFactory
        self.urlPlayerReleaseDelay = urlPlayerReleaseDelay
        bilibiliVolume = context.defaults.object(forKey: "bilibiliMusicVolume") as? Double ?? 0.8
        localVolume = context.defaults.object(forKey: "localMusicVolume") as? Double ?? 0.8
        super.init(context: context)
    }

    func start() {
        if let urlPlayer {
            configureURLMusicPlayer(urlPlayer)
        }
        installAppleMusicWorkspaceObservers()
    }

    func shutdown() {
        cancelExternalAudioResume()
        stopAppleSyncTask()
        stopAppleClock()
        urlPlayerReleaseTask?.cancel()
        urlPlayerReleaseTask = nil
        appleRefreshTask?.cancel()
        appleArtworkTask?.cancel()
        bilibiliLoadTask?.cancel()
        localLoadTask?.cancel()
        unloadURLMusicPlayer()
        appleMusicWorkspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appleMusicWorkspaceObservers.removeAll()
    }

    func configureURLMusicPlayer(_ player: any URLMusicPlaying) {
        player.setVolume(bilibiliVolume)
        player.onStateChange = { [weak self] state in
            guard let self,
                  self.activePlaybackSource == .bilibili || self.activePlaybackSource == .local else {
                return
            }
            if self.playbackState != state {
                self.setPlaybackState(state)
            }
        }
        player.onProgress = { [weak self] position, duration in
            guard let self,
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
            self.context.lyricsCoordinator.updateLyric()
            self.context.libraryController.persistProgressIfNeeded()
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
        guard urlPlayer != nil else { return }
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
}
