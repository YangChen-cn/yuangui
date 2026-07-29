import AppKit
import Combine
import Foundation

extension MusicLibraryController {
    func applyRestoredLibrary(_ snapshot: MusicLibrarySnapshot) {
        playlist = snapshot.playlist
        playMode = snapshot.playMode
        favoriteTrackIDs = snapshot.favoriteTrackIDs
        savedPlaylists = snapshot.savedPlaylists
        lyricOffsets = snapshot.lyricOffsets
        lyricsDomain.lyricsByTrackID = snapshot.lyricsByTrackID
        playbackDomain.currentTrackID = snapshot.currentTrackID
        localDomain.scheduleArtworkPrune(
            keeping: Set(snapshot.playlist.compactMap(\.localArtworkCacheKey))
        )
        playbackDomain.rebuildMusicPlaybackQueue()
        playbackDomain.lastBilibiliPosition = snapshot.lastPosition
        if browsingSource == .bilibili || browsingSource == .local {
            playbackDomain.restoreSelection(
                for: browsingSource,
                position: snapshot.lastPosition
            )
        }
        else if let currentTrack {
            lyricsDomain.loadLyrics(for: currentTrack)
        }
    }

    func persistProgressIfNeeded() {
        let second = Int(position)
        guard second != lastSavedSecond, second % 15 == 0 else { return }
        lastSavedSecond = second; persistLibrary()
    }

    func persistLibrary() {
        persistence.scheduleSave(librarySnapshot())
    }

    func librarySnapshot() -> MusicLibrarySnapshot {
        MusicLibrarySnapshot(
            playlist: playlist,
            playMode: playMode,
            currentTrackID: playbackDomain.currentTrackID,
            lastPosition: activePlaybackSource == .bilibili || activePlaybackSource == .local
                ? position
                : playbackDomain.lastBilibiliPosition,
            favoriteTrackIDs: favoriteTrackIDs,
            savedPlaylists: savedPlaylists,
            lyricOffsets: lyricOffsets,
            lyricsByTrackID: lyricsDomain.lyricsByTrackID
        )
    }
}
