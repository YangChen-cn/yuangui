import Foundation

@MainActor
final class MusicPersistenceCoordinator {
    private let library: any MusicLibraryCoordinating
    private let tasks = MusicTaskRegistry()
    private(set) var revision: UInt64 = 0

    init(library: any MusicLibraryCoordinating) {
        self.library = library
    }

    func loadIfUnchanged() async -> MusicLibrarySnapshot? {
        let revisionBeforeLoad = revision
        guard let snapshot = try? await library.load(),
              revision == revisionBeforeLoad else {
            return nil
        }
        return snapshot
    }

    func scheduleSave(_ snapshot: MusicLibrarySnapshot) {
        revision &+= 1
        let revision = revision
        tasks.launch(key: "save:\(revision)", replacingExisting: false) {
            [library] _ in
            await library.scheduleSave(snapshot, revision: revision)
        }
    }

    func saveNow(_ snapshot: MusicLibrarySnapshot) async {
        revision &+= 1
        await library.saveNow(snapshot, revision: revision)
    }

    func shutdown(saving snapshot: MusicLibrarySnapshot) async {
        await tasks.shutdown()
        await saveNow(snapshot)
    }
}
