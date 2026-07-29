import Foundation

extension MusicLibraryController {
    func remove(_ track: MusicTrack) {
        let wasCurrent = currentTrack?.id == track.id
        let removedSource = track.source
        playlist.removeAll { $0.id == track.id }
        if let key = track.localArtworkCacheKey {
            localDomain.scheduleArtworkRemoval(
                keys: localDomain.orphanedArtworkKeys(among: [key])
            )
        }
        favoriteTrackIDs.remove(track.id)
        lyricsDomain.removeCachedLyrics(for: track)
        for index in savedPlaylists.indices {
            savedPlaylists[index].trackIDs.removeAll { $0 == track.id }
        }
        if wasCurrent {
            playbackDomain.urlPlayer?.stop()
            playbackDomain.clearLoadedURLIdentity()
            currentTrack = nil
            playbackDomain.currentTrackID = nil
            playbackDomain.setPlaybackState(.stopped)
            playbackDomain.releaseScopedLocalURL()
            if removedSource == .bilibili {
                playbackDomain.lastBilibiliPosition = 0
            }
            if activePlaybackSource == removedSource {
                activePlaybackSource = nil
                playbackDomain.scheduleURLMusicPlayerRelease()
            }
            playbackProgress.reset()
            lyricsDomain.cancelLyricLoad()
            lyrics = nil
            currentLyric = nil
            nextLyric = nil
            currentLyricIndex = nil
        }
        playbackDomain.rebuildMusicPlaybackQueue()
        persistLibrary()
    }

    func clearPlaylist() {
        let source = browsingSource
        guard source != .appleMusic else { return }
        let removedTracks = playlist.filter { $0.source == source }
        let removedIDs = Set(removedTracks.map(\.id))
        for track in removedTracks {
            lyricsDomain.removeCachedLyrics(for: track)
        }
        playlist.removeAll { $0.source == source }
        localDomain.scheduleArtworkRemoval(
            keys: localDomain.orphanedArtworkKeys(
                among: Set(removedTracks.compactMap(\.localArtworkCacheKey))
            )
        )
        favoriteTrackIDs.subtract(removedIDs)
        for index in savedPlaylists.indices {
            savedPlaylists[index].trackIDs.removeAll { removedIDs.contains($0) }
        }
        if currentTrack?.source == source {
            playbackDomain.urlPlayer?.stop()
            playbackDomain.clearLoadedURLIdentity()
            playbackDomain.releaseScopedLocalURL()
            playbackDomain.currentTrackID = nil
        }
        if source == .bilibili {
            playbackDomain.lastBilibiliPosition = 0
        }
        if activePlaybackSource == source || currentTrack?.source == source {
            activePlaybackSource = nil
            playbackDomain.scheduleURLMusicPlayerRelease()
            currentTrack = nil
            playbackDomain.setPlaybackState(.stopped)
            playbackProgress.reset()
            lyricsDomain.cancelLyricLoad()
            lyrics = nil
            currentLyric = nil
            nextLyric = nil
            currentLyricIndex = nil
        }
        playbackDomain.rebuildMusicPlaybackQueue()
        persistLibrary()
    }

    func isFavorite(_ track: MusicTrack) -> Bool {
        favoriteTrackIDs.contains(track.id)
    }

    func toggleFavorite(_ track: MusicTrack) {
        if favoriteTrackIDs.contains(track.id) {
            favoriteTrackIDs.remove(track.id)
        } else {
            favoriteTrackIDs.insert(track.id)
        }
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
              !savedPlaylists[index].trackIDs.contains(track.id) else {
            return
        }
        savedPlaylists[index].trackIDs.append(track.id)
        persistLibrary()
    }

    func remove(_ track: MusicTrack, from savedPlaylist: SavedMusicPlaylist) {
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }) else {
            return
        }
        savedPlaylists[index].trackIDs.removeAll { $0 == track.id }
        persistLibrary()
    }

    func tracks(in savedPlaylist: SavedMusicPlaylist) -> [MusicTrack] {
        libraryStore.tracks(in: savedPlaylist)
    }
}
