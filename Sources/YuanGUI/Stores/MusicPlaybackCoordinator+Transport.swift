import AppKit
import Combine
import Foundation

extension MusicPlaybackCoordinator {
    func play(_ track: MusicTrack, at savedPosition: TimeInterval = 0) {
        guard !isShuttingDown else { return }
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
        guard !isShuttingDown else { return }
        guard isPlaying else { return }
        pausedForExternalAudio = true
        switch playbackSource {
        case .appleMusic:
            lastAppleClockTime = nil
            setPlaybackState(.paused)
            tasks.launch(key: "external-audio-pause") { [appleMusic] _ in
                await appleMusic.pause()
            }
        case .bilibili:
            urlPlayer?.pause()
        case .local:
            urlPlayer?.pause()
        }
    }

    func resumeAfterExternalAudio() {
        guard !isShuttingDown else { return }
        guard pausedForExternalAudio else { return }
        pausedForExternalAudio = false
        switch playbackSource {
        case .appleMusic:
            guard appleMusicRunning else { return }
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            setPlaybackState(.playing)
            tasks.launch(key: "external-audio-resume") {
                [weak self, appleMusic] generation in
                await appleMusic.play()
                guard let self, tasks.isCurrent(generation) else { return }
                scheduleAppleRefresh()
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
        guard !isShuttingDown else { return }
        guard track.source == .bilibili else { return }
        activatePlaybackSource(.bilibili)
        _ = ensureURLMusicPlayer()
        currentTrack = track
        currentTrackID = track.id
        if rebuildQueue { rebuildMusicPlaybackQueue() }
        lastBilibiliPosition = savedPosition
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        setPlaybackState(.loading)
        delegate?.reportBilibiliPlaybackError(nil)
        bilibiliRefreshAttempted = false
        delegate?.loadPlaybackLyrics(for: track)
        loadBilibiliTrack(track, position: savedPosition)
    }

    func playLocalTrack(
        _ track: MusicTrack,
        at savedPosition: TimeInterval = 0,
        rebuildQueue: Bool
    ) {
        guard !isShuttingDown else { return }
        guard track.source == .local else { return }
        activatePlaybackSource(.local)
        let player = ensureURLMusicPlayer()
        player.setVolume(localVolume)
        currentTrack = track
        currentTrackID = track.id
        if rebuildQueue { rebuildMusicPlaybackQueue() }
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        setPlaybackState(.loading)
        delegate?.reportLocalPlaybackError(nil, relocating: nil)
        delegate?.loadPlaybackLyrics(for: track)
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
                delegate?.persistPlaybackLibrary()
            } catch {
                guard !Task.isCancelled else { return }
                setPlaybackState(.failed(error.localizedDescription))
                let relocationTrack: MusicTrack?
                if error as? LocalMusicImportError == .staleBookmark
                    || error as? LocalMusicImportError == .missingFile {
                    relocationTrack = track
                } else {
                    relocationTrack = nil
                }
                delegate?.reportLocalPlaybackError(
                    error.localizedDescription,
                    relocating: relocationTrack
                )
            }
            localLoadTask = nil
        }
    }

    func loadBilibiliTrack(_ track: MusicTrack, position savedPosition: TimeInterval) {
        guard !isShuttingDown else { return }
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
                delegate?.persistPlaybackLibrary()
            } catch {
                guard !Task.isCancelled, activePlaybackSource == .bilibili else { return }
                setPlaybackState(.failed(error.localizedDescription))
                delegate?.reportBilibiliPlaybackError(error.localizedDescription)
            }
            bilibiliLoadTask = nil
        }
    }

}
