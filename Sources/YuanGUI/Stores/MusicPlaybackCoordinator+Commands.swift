import AppKit
import Combine
import Foundation

extension MusicPlaybackCoordinator {
    func setSource(_ newSource: MusicSource) {
        guard !isShuttingDown else { return }
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
        rebuildMusicPlaybackQueue()
    }

    @discardableResult
    func activatePlaybackSource(_ newSource: MusicSource) -> Bool {
        guard !isShuttingDown else { return false }
        guard activePlaybackSource != newSource else { return false }
        switch activePlaybackSource {
        case .appleMusic:
            stopAppleSyncTask()
            stopAppleClock()
        case .bilibili:
            lastBilibiliPosition = position
            bilibiliLoadTask?.cancel()
            bilibiliLoadTask = nil
            urlPlayer?.stop()
            clearLoadedURLIdentity()
            scheduleURLMusicPlayerRelease()
        case .local:
            localLoadTask?.cancel()
            localLoadTask = nil
            urlPlayer?.stop()
            clearLoadedURLIdentity()
            releaseScopedLocalURL()
            scheduleURLMusicPlayerRelease()
        case nil:
            break
        }
        switch newSource {
        case .appleMusic:
            break
        case .local:
            tasks.launch(key: "apple-pause") { [appleMusic] _ in
                await appleMusic.pause()
            }
            if volume != localVolume { volume = localVolume }
            urlPlayer?.setVolume(localVolume)
        case .bilibili:
            tasks.launch(key: "apple-pause") { [appleMusic] _ in
                await appleMusic.pause()
            }
            if volume != bilibiliVolume { volume = bilibiliVolume }
            urlPlayer?.setVolume(bilibiliVolume)
        }
        activePlaybackSource = newSource
        return true
    }

    func clearTransientPlaybackState() {
        currentTrack = nil
        playbackProgress.reset()
        setPlaybackState(.stopped)
        delegate?.reportBilibiliPlaybackError(nil)
        delegate?.resetPlaybackLyrics()
    }

    func connectAppleMusic(autoplay: Bool = false) {
        guard !isShuttingDown else { return }
        registerManualPlaybackControl()
        setSource(.appleMusic)
        if activatePlaybackSource(.appleMusic) { clearTransientPlaybackState() }
        if !appleMusicRunning {
            openAppleMusic()
            tasks.launch(key: "apple-connect-delay") { [weak self] generation in
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, tasks.isCurrent(generation) else { return }
                finishAppleMusicConnection(autoplay: autoplay)
            }
        } else {
            finishAppleMusicConnection(autoplay: autoplay)
        }
    }

    func finishAppleMusicConnection(autoplay: Bool) {
        guard !isShuttingDown else { return }
        tasks.launch(key: "apple-connect") { [weak self] generation in
            guard let self, activePlaybackSource == .appleMusic else { return }
            await refreshAppleMusic()
            guard tasks.isCurrent(generation),
                  activePlaybackSource == .appleMusic else {
                return
            }
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
        guard !isShuttingDown else { return }
        registerManualPlaybackControl()
        delegate?.reportBilibiliPlaybackError(nil)
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
            tasks.launch(key: "apple-play-pause") { [weak self, appleMusic] generation in
                await appleMusic.playPause()
                guard let self, tasks.isCurrent(generation) else { return }
                scheduleAppleRefresh()
            }
        case .bilibili:
            guard let urlPlayer else {
                if let currentTrack { play(currentTrack, at: position) }
                else if let first = playlist.first { play(first) }
                return
            }
            if let currentTrack, !hasLoadedCurrentURLTrack(currentTrack) {
                play(currentTrack, at: position)
            } else if currentTrack == nil, let first = playlist.first {
                play(first)
            } else {
                urlPlayer.playPause()
            }
        case .local:
            guard let urlPlayer else {
                if let currentTrack, currentTrack.source == .local { play(currentTrack, at: position) }
                else if let first = playlist.first(where: { $0.source == .local }) { play(first) }
                return
            }
            if let currentTrack, !hasLoadedCurrentURLTrack(currentTrack) {
                play(currentTrack, at: position)
            } else {
                urlPlayer.playPause()
            }
        }
    }

    func previous() {
        guard !isShuttingDown else { return }
        registerManualPlaybackControl()
        move(by: -1)
    }

    func next() {
        guard !isShuttingDown else { return }
        registerManualPlaybackControl()
        move(by: 1)
    }

    func seek(to newPosition: TimeInterval) {
        guard !isShuttingDown else { return }
        registerManualPlaybackControl()
        let lowerBounded = max(newPosition, 0)
        let target = duration > 0 ? min(lowerBounded, duration) : lowerBounded
        playbackProgress.setPosition(target)
        if playbackSource == .bilibili { lastBilibiliPosition = target }
        if playbackSource == .appleMusic {
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            tasks.launch(key: "apple-seek") { [appleMusic] _ in
                await appleMusic.seek(to: target)
            }
        } else if playbackSource == .bilibili || playbackSource == .local {
            urlPlayer?.seek(to: target)
        }
        delegate?.updatePlaybackLyric()
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
        guard !isShuttingDown else { return }
        volume = min(max(newValue, 0), 1)
        if playbackSource == .appleMusic {
            tasks.launch(key: "apple-volume") { [appleMusic, volume] _ in
                await appleMusic.setVolume(volume)
            }
        } else if playbackSource == .bilibili {
            bilibiliVolume = volume
            urlPlayer?.setVolume(volume)
            defaults.set(volume, forKey: "bilibiliMusicVolume")
        } else {
            localVolume = volume
            urlPlayer?.setVolume(volume)
            defaults.set(volume, forKey: "localMusicVolume")
        }
    }

    func setPlayMode(_ mode: MusicPlayMode) {
        guard !isShuttingDown else { return }
        guard playMode != mode else { return }
        playMode = mode
        rebuildMusicPlaybackQueue()
        delegate?.persistPlaybackLibrary()
    }

}
