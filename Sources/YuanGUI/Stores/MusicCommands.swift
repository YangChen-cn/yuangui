import AppKit
import Foundation

@MainActor
protocol MusicPlaybackCommanding: AnyObject {
    var canControl: Bool { get }

    func setSource(_ source: MusicSource)
    func connectAppleMusic(autoplay: Bool)
    func openAppleMusic()
    func openAutomationSettings()
    func playPause()
    func previous()
    func next()
    func seek(to position: TimeInterval)
    func setVolume(_ volume: Double)
    func setPlayMode(_ mode: MusicPlayMode)
    func play(_ track: MusicTrack, at position: TimeInterval)
    func pauseForExternalAudio()
    func resumeAfterExternalAudio()
    func cancelExternalAudioResume()
}

@MainActor
protocol MusicLyricsCommanding: AnyObject {
    func toggleLyricsVisible()
    func setLightSingAlongEnabled(_ enabled: Bool)
    func setLyricsPanelLocked(_ locked: Bool)
    func setLyricsFontSize(_ size: Double)
    func setLyricsFontStyle(_ style: LyricsFontStyle)
    func setLyricsColor(_ color: NSColor)
    func setLyricsShadowEnabled(_ enabled: Bool)
    func setLyricsBackgroundVisible(_ visible: Bool)
    func setLyricsBackgroundOpacity(_ opacity: Double)
    func setLyricOffset(_ offset: TimeInterval)
    func seek(toLyric line: TimedLyricLine)
    func searchLyrics(title: String, artist: String)
    func updateCurrentTrackMetadata(title: String, artist: String) -> Bool
    func importLRC(from url: URL)
}

@MainActor
protocol MusicLibraryCommanding: AnyObject {
    func remove(_ track: MusicTrack)
    func clearPlaylist()
    func isFavorite(_ track: MusicTrack) -> Bool
    func toggleFavorite(_ track: MusicTrack)
    func createPlaylist(named name: String) -> SavedMusicPlaylist?
    func deletePlaylist(_ playlist: SavedMusicPlaylist)
    func add(_ track: MusicTrack, to playlist: SavedMusicPlaylist)
    func remove(_ track: MusicTrack, from playlist: SavedMusicPlaylist)
    func tracks(in playlist: SavedMusicPlaylist) -> [MusicTrack]
}

@MainActor
protocol BilibiliMusicCommanding: AnyObject {
    func importBilibili()
    func playLastBilibiliImport()
    func dismissBilibiliImportResult()
    func loadBilibiliFavoriteFolders()
    func importBilibiliFavoriteFolder(_ folder: BilibiliFavoriteFolder)
    func cancelBilibiliFavoriteOperation()
    func refreshBilibiliAccount()
    func startBilibiliLogin()
    func cancelBilibiliLogin()
    func logoutBilibili()
}

@MainActor
protocol LocalMusicCommanding: AnyObject {
    func importLocalMusic(_ urls: [URL])
    func cancelLocalImport()
    func relocate(_ track: MusicTrack, to url: URL)
    func revealInFinder(_ track: MusicTrack)
    func setArtwork(for track: MusicTrack, from url: URL)
    func removeArtwork(for track: MusicTrack)
}

extension MusicFeature:
    MusicPlaybackCommanding,
    MusicLibraryCommanding,
    MusicLyricsCommanding,
    BilibiliMusicCommanding,
    LocalMusicCommanding {}
