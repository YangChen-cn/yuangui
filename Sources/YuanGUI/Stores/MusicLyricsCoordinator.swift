import AppKit
import Foundation

@MainActor
final class MusicLyricsCoordinator: MusicDomainCoordinator {
    let lyricsService: any LyricsProviding
    let localMusicImporter: any LocalMusicImporting
    let bilibili: any BilibiliMusicProviding

    var lyricLoadTask: Task<Void, Never>?
    var lyricsSearchTask: Task<Void, Never>?
    var lyricsByTrackID: [String: LyricsDocument] = [:]
    var lyricLoadRevision: UInt64 = 0

    init(
        context: MusicFeatureContext,
        lyricsService: any LyricsProviding,
        localMusicImporter: any LocalMusicImporting,
        bilibili: any BilibiliMusicProviding
    ) {
        self.lyricsService = lyricsService
        self.localMusicImporter = localMusicImporter
        self.bilibili = bilibili
        super.init(context: context)
    }

    func shutdown() {
        lyricLoadRevision &+= 1
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        cancelSearch()
    }

    func cancelSearch() {
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
    }

    func seek(to line: TimedLyricLine) {
        let target = MusicPlaybackCoordinator.lyricSeekPosition(
            for: line,
            offset: currentLyricOffset,
            duration: duration
        )
        context.playbackCoordinator.seek(to: target)
    }
}
