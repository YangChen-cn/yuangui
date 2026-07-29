import AppKit
import Combine
import Foundation

extension MusicPlaybackCoordinator {
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
            urlPlayer?.pause()
        case .local:
            urlPlayer?.pause()
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
            guard let currentTrack, hasLoadedCurrentURLTrack(currentTrack) else { return }
            guard let urlPlayer else { return }
            urlPlayer.play()
        case .local:
            guard let currentTrack, hasLoadedCurrentURLTrack(currentTrack) else { return }
            guard let urlPlayer else { return }
            urlPlayer.play()
        }
    }

    func cancelExternalAudioResume() {
        let hadAutomaticPause = pausedForExternalAudio
        pausedForExternalAudio = false
        if hadAutomaticPause { onExternalAudioResumeCancelled?() }
    }

    func registerManualPlaybackControl() {
        cancelExternalAudioResume()
        onExternalAudioManualControl?()
    }

    func playBilibiliTrack(
        _ track: MusicTrack,
        at savedPosition: TimeInterval = 0,
        rebuildQueue: Bool
    ) {
        guard track.source == .bilibili else { return }
        activatePlaybackSource(.bilibili)
        _ = ensureURLMusicPlayer()
        currentTrack = track
        currentTrackID = track.id
        if rebuildQueue { rebuildMusicPlaybackQueue() }
        lastBilibiliPosition = savedPosition
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        setPlaybackState(.loading)
        errorMessage = nil
        bilibiliRefreshAttempted = false
        context.lyricsCoordinator.loadLyrics(for: track)
        loadBilibiliTrack(track, position: savedPosition)
    }

    func playLocalTrack(
        _ track: MusicTrack,
        at savedPosition: TimeInterval = 0,
        rebuildQueue: Bool
    ) {
        guard track.source == .local else { return }
        activatePlaybackSource(.local)
        let player = ensureURLMusicPlayer()
        player.setVolume(localVolume)
        currentTrack = track
        currentTrackID = track.id
        if rebuildQueue { rebuildMusicPlaybackQueue() }
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        setPlaybackState(.loading)
        localImportStore.errorMessage = nil
        localImportStore.trackNeedingRelocation = nil
        context.lyricsCoordinator.loadLyrics(for: track)
        localLoadTask?.cancel()
        localLoadTask = Task { [weak self, localMusicImporter] in
            guard let self else { return }
            do {
                let url = try await localMusicImporter.resolveURL(for: track)
                guard !Task.isCancelled,
                      activePlaybackSource == .local,
                      currentTrack?.id == track.id else { return }
                releaseScopedLocalURL()
                guard url.startAccessingSecurityScopedResource() else {
                    throw LocalMusicImportError.securityScopeUnavailable
                }
                scopedLocalURL = url
                player.load(urls: [url], headers: [:], position: savedPosition, autoplay: true)
                loadedURLTrackID = track.id
                loadedURLSource = .local
                context.libraryController.persistLibrary()
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

    func loadBilibiliTrack(_ track: MusicTrack, position savedPosition: TimeInterval) {
        bilibiliLoadTask?.cancel()
        bilibiliLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let location = try await bilibili.audioLocation(for: track)
                let headers = await bilibili.playbackHeaders()
                guard !Task.isCancelled,
                      activePlaybackSource == .bilibili,
                      currentTrack?.id == track.id else { return }
                guard let urlPlayer else { return }
                urlPlayer.load(
                    urls: location.candidates,
                    headers: headers,
                    position: savedPosition,
                    autoplay: true
                )
                loadedURLTrackID = track.id
                loadedURLSource = .bilibili
                context.libraryController.persistLibrary()
            } catch {
                guard !Task.isCancelled, activePlaybackSource == .bilibili else { return }
                setPlaybackState(.failed(error.localizedDescription))
                errorMessage = error.localizedDescription
            }
            bilibiliLoadTask = nil
        }
    }

}
