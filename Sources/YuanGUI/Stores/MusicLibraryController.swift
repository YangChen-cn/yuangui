import Foundation

@MainActor
protocol MusicLibraryPlaybackAccess: AnyObject {
    var libraryBrowsingSource: MusicSource { get }
    var libraryActivePlaybackSource: MusicSource? { get }
    var libraryCurrentTrack: MusicTrack? { get }
    var libraryCurrentTrackID: String? { get set }
    var libraryLastBilibiliPosition: TimeInterval { get set }
    var libraryPlaybackPosition: TimeInterval { get }
    var libraryPlayMode: MusicPlayMode { get set }
    var libraryUpcomingTrackIDs: [String] { get }

    func removeTrackFromPlayback(_ track: MusicTrack)
    func clearPlayback(for source: MusicSource)
    func rebuildLibraryPlaybackQueue()
    func restoreLibrarySelection(for source: MusicSource, position: TimeInterval)
    func refreshCurrentPlaybackTrack(_ track: MusicTrack)
}

@MainActor
protocol MusicLibraryLyricsAccess: AnyObject {
    var libraryLyricOffsets: [String: TimeInterval] { get set }
    var libraryLyricsCache: [String: LyricsDocument] { get set }

    func removeLibraryCachedLyrics(for track: MusicTrack)
    func resetLibraryLyrics()
    func loadLibraryLyrics(for track: MusicTrack)
}

@MainActor
protocol MusicLibraryArtworkAccess: AnyObject {
    func scheduleLibraryArtworkRemoval(keys: Set<String>)
    func orphanedLibraryArtworkKeys(among candidates: Set<String>) -> Set<String>
    func pruneLibraryArtwork(keeping keys: Set<String>)
}

@MainActor
final class MusicLibraryController {
    weak var playbackAccess: (any MusicLibraryPlaybackAccess)?
    weak var lyricsAccess: (any MusicLibraryLyricsAccess)?
    weak var artworkAccess: (any MusicLibraryArtworkAccess)?

    let store: MusicLibraryStore
    let persistence: MusicPersistenceCoordinator
    var libraryRestoreTask: Task<Void, Never>?
    var lastSavedSecond = -1
    var isShuttingDown = false

    init(
        store: MusicLibraryStore,
        persistence: MusicPersistenceCoordinator
    ) {
        self.store = store
        self.persistence = persistence
    }

    var playlist: [MusicTrack] {
        get { store.playlist }
        set { store.playlist = newValue }
    }
    var favoriteTrackIDs: Set<String> {
        get { store.favoriteTrackIDs }
        set { store.favoriteTrackIDs = newValue }
    }
    var savedPlaylists: [SavedMusicPlaylist] {
        get { store.savedPlaylists }
        set { store.savedPlaylists = newValue }
    }
    var favoriteTracks: [MusicTrack] { store.favoriteTracks }
    var upcomingTracks: [MusicTrack] {
        let tracksByID = Dictionary(
            playlist.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        return (playbackAccess?.libraryUpcomingTrackIDs ?? [])
            .compactMap { tracksByID[$0] }
    }

    func start() {
        libraryRestoreTask = Task { [weak self, persistence] in
            guard let snapshot = await persistence.loadIfUnchanged(),
                  !Task.isCancelled,
                  let self,
                  !isShuttingDown else {
                return
            }
            applyRestoredLibrary(snapshot)
            libraryRestoreTask = nil
        }
    }

    func shutdown() async {
        isShuttingDown = true
        libraryRestoreTask?.cancel()
        await libraryRestoreTask?.value
        libraryRestoreTask = nil
        await persistence.shutdown(saving: librarySnapshot())
    }
}
