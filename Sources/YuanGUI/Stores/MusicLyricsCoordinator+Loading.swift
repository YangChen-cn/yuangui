import AppKit
import Combine
import Foundation

extension MusicLyricsCoordinator {
    func loadLyrics(for track: MusicTrack) {
        guard !isShuttingDown else { return }
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
                    delegate?.persistLyricsChanges()
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
                delegate?.persistLyricsChanges()
            }
            updateLyric()
            finishLyricLoad(revision, trackID: track.id)
        }
    }

    func cancelLyricLoad() {
        lyricLoadRevision &+= 1
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        if isLoadingLyrics { isLoadingLyrics = false }
    }

    func isCurrentLyricLoad(_ revision: UInt64, trackID: String) -> Bool {
        !isShuttingDown
            && !Task.isCancelled
            && lyricLoadRevision == revision
            && currentTrack?.id == trackID
    }

    func finishLyricLoad(_ revision: UInt64, trackID: String) {
        guard lyricLoadRevision == revision, currentTrack?.id == trackID else { return }
        if isLoadingLyrics { isLoadingLyrics = false }
        lyricLoadTask = nil
    }

    func refreshCurrentBilibiliSubtitleAfterLogin() async {
        guard !isShuttingDown,
              let track = currentTrack,
              track.source == .bilibili,
              let subtitleURL = await bilibili.subtitleURL(for: track),
              !Task.isCancelled,
              !isShuttingDown,
              currentTrack?.id == track.id else {
            return
        }
        updateSubtitleURL(subtitleURL, for: track.id)
        if cachedLyrics(for: track)?.source == "LRCLIB" {
            removeCachedLyrics(for: track)
        }
        loadLyrics(for: currentTrack ?? track)
    }

    func updateSubtitleURL(_ url: URL, for trackID: String) {
        delegate?.updateLyricsSubtitleURL(url, trackID: trackID)
        delegate?.persistLyricsChanges()
    }

    func cachedLyrics(for track: MusicTrack) -> LyricsDocument? {
        if let cached = lyricsByTrackID[track.lyricsCacheKey] ?? lyricsByTrackID[track.id] {
            return cached
        }
        guard track.source == .appleMusic,
              let legacy = lyricsByTrackID.first(where: { track.matchesLegacyLyricsCacheKey($0.key) }) else {
            return nil
        }
        lyricsByTrackID[track.lyricsCacheKey] = legacy.value
        lyricsByTrackID.removeValue(forKey: legacy.key)
        delegate?.persistLyricsChanges()
        return legacy.value
    }

    func cacheLyrics(_ document: LyricsDocument, for track: MusicTrack) {
        lyricsByTrackID[track.lyricsCacheKey] = document
        if track.lyricsCacheKey != track.id {
            lyricsByTrackID.removeValue(forKey: track.id)
        }
    }

    func removeCachedLyrics(for track: MusicTrack) {
        lyricsByTrackID.removeValue(forKey: track.lyricsCacheKey)
        lyricsByTrackID.removeValue(forKey: track.id)
        if track.source == .appleMusic {
            lyricsByTrackID.keys
                .filter { track.matchesLegacyLyricsCacheKey($0) }
                .forEach { lyricsByTrackID.removeValue(forKey: $0) }
        }
    }

    func updateLyric() {
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

}
