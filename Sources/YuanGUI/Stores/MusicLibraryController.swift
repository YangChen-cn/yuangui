import Foundation

@MainActor
final class MusicLibraryController: MusicDomainCoordinator {
    let persistence: MusicPersistenceCoordinator
    var libraryRestoreTask: Task<Void, Never>?
    var lastSavedSecond = -1

    init(
        context: MusicFeatureContext,
        persistence: MusicPersistenceCoordinator
    ) {
        self.persistence = persistence
        super.init(context: context)
    }

    var favoriteTracks: [MusicTrack] {
        libraryStore.favoriteTracks
    }

    var upcomingTracks: [MusicTrack] {
        let tracksByID = Dictionary(
            playlist.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        return upcomingTrackIDs.compactMap { tracksByID[$0] }
    }

    func start() {
        libraryRestoreTask = Task { [weak self, persistence] in
            guard let snapshot = await persistence.loadIfUnchanged(),
                  !Task.isCancelled,
                  let self else {
                return
            }
            applyRestoredLibrary(snapshot)
            libraryRestoreTask = nil
        }
    }

    func shutdown() async {
        cancelPendingRestore()
        await persistence.saveNow(librarySnapshot())
    }

    func cancelPendingRestore() {
        libraryRestoreTask?.cancel()
        libraryRestoreTask = nil
    }
}
