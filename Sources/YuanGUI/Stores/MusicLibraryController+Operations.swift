import Foundation

extension MusicLibraryController {
    func remove(_ track: MusicTrack) {
        guard !isShuttingDown else { return }
        let wasCurrent = playbackAccess?.libraryCurrentTrack?.id == track.id
        playlist.removeAll { $0.id == track.id }
        if let key = track.localArtworkCacheKey {
            artworkAccess?.scheduleLibraryArtworkRemoval(
                keys: artworkAccess?.orphanedLibraryArtworkKeys(among: [key]) ?? []
            )
        }
        favoriteTrackIDs.remove(track.id)
        lyricsAccess?.removeLibraryCachedLyrics(for: track)
        for index in savedPlaylists.indices {
            savedPlaylists[index].trackIDs.removeAll { $0 == track.id }
        }
        if wasCurrent {
            playbackAccess?.removeTrackFromPlayback(track)
            lyricsAccess?.resetLibraryLyrics()
        }
        playbackAccess?.rebuildLibraryPlaybackQueue()
        persistLibrary()
    }

    func clearPlaylist() {
        guard !isShuttingDown else { return }
        guard let source = playbackAccess?.libraryBrowsingSource else { return }
        guard source != .appleMusic else { return }
        let removedTracks = playlist.filter { $0.source == source }
        let removedIDs = Set(removedTracks.map(\.id))
        for track in removedTracks {
            lyricsAccess?.removeLibraryCachedLyrics(for: track)
        }
        playlist.removeAll { $0.source == source }
        artworkAccess?.scheduleLibraryArtworkRemoval(
            keys: artworkAccess?.orphanedLibraryArtworkKeys(
                among: Set(removedTracks.compactMap(\.localArtworkCacheKey))
            ) ?? []
        )
        favoriteTrackIDs.subtract(removedIDs)
        for index in savedPlaylists.indices {
            savedPlaylists[index].trackIDs.removeAll { removedIDs.contains($0) }
        }
        playbackAccess?.clearPlayback(for: source)
        lyricsAccess?.resetLibraryLyrics()
        playbackAccess?.rebuildLibraryPlaybackQueue()
        persistLibrary()
    }

    func isFavorite(_ track: MusicTrack) -> Bool {
        favoriteTrackIDs.contains(track.id)
    }

    func toggleFavorite(_ track: MusicTrack) {
        guard !isShuttingDown else { return }
        if favoriteTrackIDs.contains(track.id) {
            favoriteTrackIDs.remove(track.id)
        } else {
            favoriteTrackIDs.insert(track.id)
        }
        persistLibrary()
    }

    @discardableResult
    func createPlaylist(named rawName: String) -> SavedMusicPlaylist? {
        guard !isShuttingDown else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let playlist = SavedMusicPlaylist(name: name)
        savedPlaylists.append(playlist)
        persistLibrary()
        return playlist
    }

    func deletePlaylist(_ savedPlaylist: SavedMusicPlaylist) {
        guard !isShuttingDown else { return }
        savedPlaylists.removeAll { $0.id == savedPlaylist.id }
        persistLibrary()
    }

    func add(_ track: MusicTrack, to savedPlaylist: SavedMusicPlaylist) {
        guard !isShuttingDown else { return }
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }),
              !savedPlaylists[index].trackIDs.contains(track.id) else {
            return
        }
        savedPlaylists[index].trackIDs.append(track.id)
        persistLibrary()
    }

    func remove(_ track: MusicTrack, from savedPlaylist: SavedMusicPlaylist) {
        guard !isShuttingDown else { return }
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }) else {
            return
        }
        savedPlaylists[index].trackIDs.removeAll { $0 == track.id }
        persistLibrary()
    }

    func tracks(in savedPlaylist: SavedMusicPlaylist) -> [MusicTrack] {
        store.tracks(in: savedPlaylist)
    }

    func importTracks(
        _ tracks: [MusicTrack],
        playlistName: String? = nil
    ) -> [MusicTrack] {
        guard !isShuttingDown else { return [] }
        var seen = Set(playlist.map(\.id))
        let added = tracks.filter { seen.insert($0.id).inserted }
        playlist.append(contentsOf: added)
        if let playlistName, !tracks.isEmpty {
            updateLocalPlaylist(named: playlistName, with: tracks)
        }
        return added
    }

    func updateLocalPlaylist(named name: String, with tracks: [MusicTrack]) {
        guard !tracks.isEmpty else { return }
        if let index = savedPlaylists.firstIndex(where: { $0.name == name }) {
            var existing = Set(savedPlaylists[index].trackIDs)
            savedPlaylists[index].trackIDs.append(
                contentsOf: tracks.map(\.id).filter { existing.insert($0).inserted }
            )
        } else {
            var seen = Set<String>()
            savedPlaylists.append(
                SavedMusicPlaylist(
                    name: name,
                    trackIDs: tracks.map(\.id).filter { seen.insert($0).inserted }
                )
            )
        }
    }

    func track(withID id: String) -> MusicTrack? {
        playlist.first { $0.id == id }
    }

    var localDuplicateKeys: Set<String> {
        Set(playlist.compactMap(\.localDuplicateKey))
    }

    var referencedArtworkKeys: Set<String> {
        Set(playlist.compactMap(\.localArtworkCacheKey))
    }

    func appendImportedLocalTracks(_ tracks: [MusicTrack]) {
        guard !isShuttingDown else { return }
        playlist.append(contentsOf: tracks)
    }

    func replaceTrack(_ original: MusicTrack, with updated: MusicTrack) -> Bool {
        guard !isShuttingDown else { return false }
        guard let index = playlist.firstIndex(where: { $0.id == original.id }) else {
            return false
        }
        playlist[index] = updated
        return true
    }

    func replaceArtwork(
        for trackID: String,
        with newKey: String
    ) -> (didReplace: Bool, previousKey: String?) {
        guard !isShuttingDown else { return (false, nil) }
        guard let index = playlist.firstIndex(where: { $0.id == trackID }) else {
            return (false, nil)
        }
        let previousKey = playlist[index].localArtworkCacheKey
        playlist[index].localArtworkCacheKey = newKey
        playbackAccess?.refreshCurrentPlaybackTrack(playlist[index])
        return (true, previousKey)
    }

    func removeArtwork(for trackID: String) -> String? {
        guard !isShuttingDown else { return nil }
        guard let index = playlist.firstIndex(where: { $0.id == trackID }),
              let previousKey = playlist[index].localArtworkCacheKey else {
            return nil
        }
        playlist[index].localArtworkCacheKey = nil
        playbackAccess?.refreshCurrentPlaybackTrack(playlist[index])
        return previousKey
    }

    func updateTrackMetadata(
        trackID: String,
        title: String,
        artist: String
    ) {
        guard !isShuttingDown else { return }
        guard let index = playlist.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        playlist[index].title = title
        playlist[index].artist = artist
        playbackAccess?.refreshCurrentPlaybackTrack(playlist[index])
    }

    func updateSubtitleURL(_ url: URL, trackID: String) {
        guard !isShuttingDown else { return }
        guard let index = playlist.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        playlist[index].subtitleURL = url
        playbackAccess?.refreshCurrentPlaybackTrack(playlist[index])
    }
}
