import Foundation

@MainActor
protocol LocalMusicCoordinatorDelegate: AnyObject {
    var localDuplicateKeys: Set<String> { get }
    var referencedArtworkKeys: Set<String> { get }

    func appendImportedLocalTracks(_ tracks: [MusicTrack])
    func didImportLocalTracks()
    func replaceLocalTrack(_ original: MusicTrack, with updated: MusicTrack) -> Bool
    func didRelocateCurrentLocalTrack(_ original: MusicTrack, to updated: MusicTrack)
    func replaceArtwork(
        for trackID: String,
        with newKey: String
    ) -> (didReplace: Bool, previousKey: String?)
    func removeArtwork(for trackID: String) -> String?
    func persistLocalMusicChanges()
}

@MainActor
final class LocalMusicCoordinator {
    weak var delegate: (any LocalMusicCoordinatorDelegate)?

    let importStore: LocalMusicImportStore
    let importer: any LocalMusicImporting
    let artworkRepository: any LocalMusicArtworkManaging
    let fileRevealer: any LocalMusicFileRevealing
    let tasks = MusicTaskRegistry()

    var artworkMaintenanceTasks: [Task<Void, Never>] = []

    init(
        importStore: LocalMusicImportStore,
        importer: any LocalMusicImporting,
        artworkRepository: any LocalMusicArtworkManaging,
        fileRevealer: any LocalMusicFileRevealing
    ) {
        self.importStore = importStore
        self.importer = importer
        self.artworkRepository = artworkRepository
        self.fileRevealer = fileRevealer
    }

    func shutdown() async {
        await tasks.shutdown()
        importStore.isImporting = false
        artworkMaintenanceTasks.forEach { $0.cancel() }
        for task in artworkMaintenanceTasks {
            await task.value
        }
        artworkMaintenanceTasks.removeAll()
    }

    func scheduleArtworkRemoval(keys: Set<String>) {
        guard !tasks.isShuttingDown, !keys.isEmpty else { return }
        let previous = artworkMaintenanceTasks.last
        let repository = artworkRepository
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await repository.remove(keys: keys)
        }
        artworkMaintenanceTasks.append(task)
    }

    func orphanedArtworkKeys(among candidates: Set<String>) -> Set<String> {
        candidates.subtracting(delegate?.referencedArtworkKeys ?? [])
    }

    func scheduleArtworkPrune(keeping keys: Set<String>) {
        guard !tasks.isShuttingDown else { return }
        let previous = artworkMaintenanceTasks.last
        let repository = artworkRepository
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await repository.removeOrphans(keeping: keys)
        }
        artworkMaintenanceTasks.append(task)
    }
}

extension LocalMusicCoordinator: MusicLibraryArtworkAccess {
    func scheduleLibraryArtworkRemoval(keys: Set<String>) {
        scheduleArtworkRemoval(keys: keys)
    }

    func orphanedLibraryArtworkKeys(among candidates: Set<String>) -> Set<String> {
        orphanedArtworkKeys(among: candidates)
    }

    func pruneLibraryArtwork(keeping keys: Set<String>) {
        scheduleArtworkPrune(keeping: keys)
    }
}
