import AppKit
import Combine
import Foundation

extension MusicPlaybackCoordinator {
    func refreshAppleMusic() async {
        guard !isShuttingDown, activePlaybackSource == .appleMusic else { return }
        let performanceStart = RuntimePerformance.start()
        defer { RuntimePerformance.record("music.apple.sync", since: performanceStart) }
        let running = await appleMusic.isRunning()
        guard !Task.isCancelled, !isShuttingDown else { return }
        if appleMusicRunning != running { appleMusicRunning = running }
        guard appleMusicRunning else {
            if activePlaybackSource == .appleMusic { setPlaybackState(.stopped) }
            return
        }
        do {
            let snapshot = try await appleMusic.requestSnapshot()
            guard !Task.isCancelled,
                  !isShuttingDown,
                  activePlaybackSource == .appleMusic else {
                return
            }
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
                delegate?.loadPlaybackLyrics(for: track)
                loadAppleArtwork(for: track)
            }
            delegate?.updatePlaybackLyric()
            delegate?.reportBilibiliPlaybackError(nil)
        } catch {
            guard !Task.isCancelled,
                  !isShuttingDown,
                  activePlaybackSource == .appleMusic else {
                return
            }
            delegate?.reportBilibiliPlaybackError(error.localizedDescription)
        }
    }

    func startAppleSyncTask() {
        guard !isShuttingDown,
              activePlaybackSource == .appleMusic,
              appleSyncTask == nil else { return }
        appleSyncGeneration &+= 1
        let generation = appleSyncGeneration
        appleSyncTask = Task { [weak self] in
            await self?.runAppleSyncLoop(generation: generation)
        }
    }

    func stopAppleSyncTask() {
        appleSyncGeneration &+= 1
        appleSyncTask?.cancel()
        appleSyncTask = nil
    }

    func finishAppleSyncTask(generation: UInt) {
        guard appleSyncGeneration == generation else { return }
        appleSyncTask = nil
    }

    func runAppleSyncLoop(generation: UInt) async {
        defer { finishAppleSyncTask(generation: generation) }
        while !Task.isCancelled {
            guard activePlaybackSource == .appleMusic else { return }
            await refreshAppleMusic()
            let interval = appleMusicRunning
                ? appleSyncInterval
                : appleUnavailableSyncInterval
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }

    func installAppleMusicWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          !self.isShuttingDown,
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

    func startAppleClockIfNeeded() {
        guard !isShuttingDown,
              activePlaybackSource == .appleMusic,
              playbackState.isPlaying,
              appleClockTask == nil else { return }
        appleClockGeneration &+= 1
        let generation = appleClockGeneration
        appleClockTask = Task { [weak self] in
            await self?.runAppleClock(generation: generation)
        }
    }

    func stopAppleClock() {
        appleClockGeneration &+= 1
        appleClockTask?.cancel()
        appleClockTask = nil
        lastAppleClockTime = nil
    }

    func finishAppleClockTask(generation: UInt) {
        guard appleClockGeneration == generation else { return }
        appleClockTask = nil
        lastAppleClockTime = nil
    }

    func runAppleClock(generation: UInt) async {
        defer { finishAppleClockTask(generation: generation) }
        while !Task.isCancelled {
            guard activePlaybackSource == .appleMusic, playbackState.isPlaying else { return }
            let now = Date.timeIntervalSinceReferenceDate
            if let lastAppleClockTime {
                let elapsed = min(max(now - lastAppleClockTime, 0), 1)
                let advanced = duration > 0 ? min(position + elapsed, duration) : position + elapsed
                playbackProgress.setPosition(advanced)
                delegate?.updatePlaybackLyric()
            }
            lastAppleClockTime = now
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }

    func loadAppleArtwork(for track: MusicTrack) {
        guard !isShuttingDown else { return }
        appleArtworkTask?.cancel()
        appleArtworkTask = Task { [weak self, appleMusic] in
            let url = await appleMusic.artworkURL(for: track.id)
            guard !Task.isCancelled,
                  let self,
                  !isShuttingDown,
                  currentTrack?.id == track.id else {
                return
            }
            if currentTrack?.coverURL != url { currentTrack?.coverURL = url }
            appleArtworkTask = nil
        }
    }

    func scheduleAppleRefresh() {
        guard !isShuttingDown else { return }
        appleRefreshTask?.cancel()
        appleRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await self?.refreshAppleMusic()
        }
    }

    func move(by delta: Int) {
        guard !isShuttingDown else { return }
        let controlSource = activePlaybackSource ?? currentTrack?.source ?? browsingSource
        if controlSource == .appleMusic {
            if activePlaybackSource == nil { connectAppleMusic() }
            tasks.launch(key: "apple-move") { [weak self, appleMusic] generation in
                if delta < 0 { await appleMusic.previous() } else { await appleMusic.next() }
                guard let self, tasks.isCurrent(generation) else { return }
                scheduleAppleRefresh()
            }
            return
        }
        let sourcePlaylist = playlist.filter { $0.source == controlSource }
        guard !sourcePlaylist.isEmpty else { return }
        let targetID = delta < 0
            ? musicPlaybackQueue.previousTrackID(
                playlist: sourcePlaylist, currentTrackID: currentTrack?.id, mode: playMode
            )
            : musicPlaybackQueue.nextTrackID(
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

    func handleTrackFinished() {
        guard !isShuttingDown else { return }
        guard activePlaybackSource == .bilibili || activePlaybackSource == .local else { return }
        guard !(blocksAutomaticPlaybackForExternalAudio?() ?? false) else {
            setPlaybackState(.paused)
            return
        }
        if playMode == .repeatOne, let currentTrack { play(currentTrack) }
        else { move(by: 1) }
    }

    func handleURLPlayerFailure(_ error: Error) {
        guard !isShuttingDown else { return }
        clearLoadedURLIdentity()
        if activePlaybackSource == .local {
            setPlaybackState(.failed(error.localizedDescription))
            delegate?.reportLocalPlaybackError(error.localizedDescription, relocating: nil)
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
            delegate?.reportBilibiliPlaybackError(
                AppLocalizer.format(
                    "music.bilibili.playbackExpiredDetail",
                    error.localizedDescription
                )
            )
        }
    }

    func restoreBilibiliSelection(position savedPosition: TimeInterval = 0) {
        restoreSelection(for: .bilibili, position: savedPosition)
    }

    func restoreSelection(for source: MusicSource, position savedPosition: TimeInterval = 0) {
        let sourceTracks = playlist.filter { $0.source == source }
        if let id = currentTrackID, let track = sourceTracks.first(where: { $0.id == id }) {
            let restoredPosition = min(max(savedPosition, 0), max(track.duration, 0))
            if source == .bilibili { lastBilibiliPosition = restoredPosition }
            currentTrack = track; playbackProgress.reset(position: restoredPosition, duration: track.duration); setPlaybackState(.paused)
            delegate?.loadPlaybackLyrics(for: track)
        } else if let first = sourceTracks.first {
            if source == .bilibili { lastBilibiliPosition = 0 }
            currentTrack = first; currentTrackID = first.id; playbackProgress.reset(position: 0, duration: first.duration); setPlaybackState(.paused)
            delegate?.loadPlaybackLyrics(for: first)
        } else {
            currentTrack = nil
            if source == .bilibili { lastBilibiliPosition = 0 }
            playbackProgress.reset()
            setPlaybackState(.stopped)
        }
    }

    func rebuildMusicPlaybackQueue() {
        musicPlaybackQueue.rebuild(
            playlist: playlist.filter { $0.source == (currentTrack?.source ?? browsingSource) },
            currentTrackID: currentTrackID,
            mode: playMode
        )
        publishUpcomingTracks()
    }

    func publishUpcomingTracks() {
        let ids = musicPlaybackQueue.upcomingTrackIDs
        if upcomingTrackIDs != ids { upcomingTrackIDs = ids }
    }

}
