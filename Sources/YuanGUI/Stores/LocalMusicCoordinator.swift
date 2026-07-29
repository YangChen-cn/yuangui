import Foundation

@MainActor
final class LocalMusicCoordinator: MusicDomainCoordinator {
    let importer: any LocalMusicImporting
    let artworkRepository: any LocalMusicArtworkManaging
    let fileRevealer: any LocalMusicFileRevealing

    var importTask: Task<Void, Never>?
    var artworkMaintenanceTask: Task<Void, Never>?

    init(
        context: MusicFeatureContext,
        importer: any LocalMusicImporting,
        artworkRepository: any LocalMusicArtworkManaging,
        fileRevealer: any LocalMusicFileRevealing
    ) {
        self.importer = importer
        self.artworkRepository = artworkRepository
        self.fileRevealer = fileRevealer
        super.init(context: context)
    }

    func shutdown() async {
        importTask?.cancel()
        importTask = nil
        await artworkMaintenanceTask?.value
        artworkMaintenanceTask = nil
    }

    func scheduleArtworkRemoval(keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previous = artworkMaintenanceTask
        let repository = artworkRepository
        artworkMaintenanceTask = Task {
            await previous?.value
            await repository.remove(keys: keys)
        }
    }

    func orphanedArtworkKeys(among candidates: Set<String>) -> Set<String> {
        candidates.subtracting(Set(playlist.compactMap(\.localArtworkCacheKey)))
    }

    func scheduleArtworkPrune(keeping keys: Set<String>) {
        let previous = artworkMaintenanceTask
        let repository = artworkRepository
        artworkMaintenanceTask = Task {
            await previous?.value
            await repository.removeOrphans(keeping: keys)
        }
    }
}
