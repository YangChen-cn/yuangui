import Foundation

protocol MusicLibraryPersisting: Sendable {
    func load() throws -> MusicLibrarySnapshot
    func save(_ snapshot: MusicLibrarySnapshot) throws
}

struct MusicLibraryFileStore: MusicLibraryPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuanGUI/Music/library.json")
    }

    func load() throws -> MusicLibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return MusicLibrarySnapshot() }
        return try JSONDecoder().decode(MusicLibrarySnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: MusicLibrarySnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

actor MusicLibraryActor {
    private let store: MusicLibraryPersisting
    private var pending: MusicLibrarySnapshot?
    private var saveTask: Task<Void, Never>?

    init(store: MusicLibraryPersisting = MusicLibraryFileStore()) { self.store = store }

    func load() throws -> MusicLibrarySnapshot { try store.load() }

    func scheduleSave(_ snapshot: MusicLibrarySnapshot) {
        pending = snapshot
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await self?.flush()
        }
    }

    func flush() {
        guard let pending else { return }
        self.pending = nil
        saveTask = nil
        try? store.save(pending)
    }
}
