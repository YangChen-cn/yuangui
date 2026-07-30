import AppKit
import Combine
import Foundation

extension MusicLibraryController {
    func applyRestoredLibrary(_ snapshot: MusicLibrarySnapshot) {
        playlist = snapshot.playlist
        playbackAccess?.libraryPlayMode = snapshot.playMode
        favoriteTrackIDs = snapshot.favoriteTrackIDs
        savedPlaylists = snapshot.savedPlaylists
        lyricsAccess?.libraryLyricOffsets = snapshot.lyricOffsets
        lyricsAccess?.libraryLyricsCache = snapshot.lyricsByTrackID
        playbackAccess?.libraryCurrentTrackID = snapshot.currentTrackID
        artworkAccess?.pruneLibraryArtwork(
            keeping: Set(snapshot.playlist.compactMap(\.localArtworkCacheKey))
        )
        playbackAccess?.rebuildLibraryPlaybackQueue()
        playbackAccess?.libraryLastBilibiliPosition = snapshot.lastPosition
        let source = playbackAccess?.libraryBrowsingSource
        if source == .bilibili || source == .local, let source {
            playbackAccess?.restoreLibrarySelection(
                for: source,
                position: snapshot.lastPosition
            )
        }
        else if let currentTrack = playbackAccess?.libraryCurrentTrack {
            lyricsAccess?.loadLibraryLyrics(for: currentTrack)
        }
    }

    func persistProgressIfNeeded() {
        guard !isShuttingDown else { return }
        let second = Int(playbackAccess?.libraryPlaybackPosition ?? 0)
        guard second != lastSavedSecond, second % 15 == 0 else { return }
        lastSavedSecond = second; persistLibrary()
    }

    func persistLibrary() {
        guard !isShuttingDown else { return }
        persistence.scheduleSave(librarySnapshot())
    }

    func librarySnapshot() -> MusicLibrarySnapshot {
        MusicLibrarySnapshot(
            playlist: playlist,
            playMode: playbackAccess?.libraryPlayMode ?? .sequential,
            currentTrackID: playbackAccess?.libraryCurrentTrackID,
            lastPosition: playbackAccess?.libraryActivePlaybackSource == .bilibili
                || playbackAccess?.libraryActivePlaybackSource == .local
                ? playbackAccess?.libraryPlaybackPosition ?? 0
                : playbackAccess?.libraryLastBilibiliPosition ?? 0,
            favoriteTrackIDs: favoriteTrackIDs,
            savedPlaylists: savedPlaylists,
            lyricOffsets: lyricsAccess?.libraryLyricOffsets ?? [:],
            lyricsByTrackID: lyricsAccess?.libraryLyricsCache ?? [:]
        )
    }
}
