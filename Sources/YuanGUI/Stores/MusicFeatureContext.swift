import Foundation

@MainActor
final class MusicFeatureContext {
    let playback: MusicPlaybackStore
    let library: MusicLibraryStore
    let lyrics: LyricsStore
    let lyricsPresentation: LyricsPresentationStore
    let bilibiliAccount: BilibiliAccountStore
    let bilibiliImport: BilibiliImportStore
    let localImport: LocalMusicImportStore
    let defaults: UserDefaults

    private weak var playbackCoordinatorStorage: MusicPlaybackCoordinator?
    private weak var libraryControllerStorage: MusicLibraryController?
    private weak var lyricsCoordinatorStorage: MusicLyricsCoordinator?
    private weak var bilibiliCoordinatorStorage: BilibiliMusicCoordinator?
    private weak var localCoordinatorStorage: LocalMusicCoordinator?

    var playbackCoordinator: MusicPlaybackCoordinator {
        guard let coordinator = playbackCoordinatorStorage else {
            preconditionFailure("Music playback coordinator is not bound")
        }
        return coordinator
    }
    var libraryController: MusicLibraryController {
        guard let controller = libraryControllerStorage else {
            preconditionFailure("Music library controller is not bound")
        }
        return controller
    }
    var lyricsCoordinator: MusicLyricsCoordinator {
        guard let coordinator = lyricsCoordinatorStorage else {
            preconditionFailure("Music lyrics coordinator is not bound")
        }
        return coordinator
    }
    var bilibiliCoordinator: BilibiliMusicCoordinator {
        guard let coordinator = bilibiliCoordinatorStorage else {
            preconditionFailure("Bilibili music coordinator is not bound")
        }
        return coordinator
    }
    var localCoordinator: LocalMusicCoordinator {
        guard let coordinator = localCoordinatorStorage else {
            preconditionFailure("Local music coordinator is not bound")
        }
        return coordinator
    }

    init(
        playback: MusicPlaybackStore,
        library: MusicLibraryStore,
        lyrics: LyricsStore,
        lyricsPresentation: LyricsPresentationStore,
        bilibiliAccount: BilibiliAccountStore,
        bilibiliImport: BilibiliImportStore,
        localImport: LocalMusicImportStore,
        defaults: UserDefaults
    ) {
        self.playback = playback
        self.library = library
        self.lyrics = lyrics
        self.lyricsPresentation = lyricsPresentation
        self.bilibiliAccount = bilibiliAccount
        self.bilibiliImport = bilibiliImport
        self.localImport = localImport
        self.defaults = defaults
    }

    func bind(
        playback: MusicPlaybackCoordinator,
        library: MusicLibraryController,
        lyrics: MusicLyricsCoordinator,
        bilibili: BilibiliMusicCoordinator,
        local: LocalMusicCoordinator
    ) {
        playbackCoordinatorStorage = playback
        libraryControllerStorage = library
        lyricsCoordinatorStorage = lyrics
        bilibiliCoordinatorStorage = bilibili
        localCoordinatorStorage = local
    }
}
