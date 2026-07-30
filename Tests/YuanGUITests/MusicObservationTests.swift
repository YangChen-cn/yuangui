import Combine
import Foundation
import XCTest
@testable import YuanGUI

@MainActor
final class MusicObservationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testUnrelatedStoresDoNotPublishIntoPlaybackLyricsOrProgress() {
        let playback = MusicPlaybackStore(source: .appleMusic, volume: 0.8)
        let library = MusicLibraryStore()
        let lyrics = LyricsStore()
        let account = BilibiliAccountStore()
        let importer = BilibiliImportStore()
        let localImporter = LocalMusicImportStore()

        var playbackChanges = 0
        var lyricChanges = 0
        var progressChanges = 0
        playback.objectWillChange
            .sink { playbackChanges += 1 }
            .store(in: &cancellables)
        lyrics.objectWillChange
            .sink { lyricChanges += 1 }
            .store(in: &cancellables)
        playback.progress.objectWillChange
            .sink { progressChanges += 1 }
            .store(in: &cancellables)

        library.favoriteTrackIDs.insert("track")
        account.loginPhase = .requestingQRCode
        importer.completedCount = 1
        localImporter.importedCount = 1

        XCTAssertEqual(playbackChanges, 0)
        XCTAssertEqual(lyricChanges, 0)
        XCTAssertEqual(progressChanges, 0)
    }

    func testPlaybackProgressPublishesWithoutInvalidatingPlaybackStore() {
        let playback = MusicPlaybackStore(source: .appleMusic, volume: 0.8)
        var playbackChanges = 0
        var progressChanges = 0
        playback.objectWillChange
            .sink { playbackChanges += 1 }
            .store(in: &cancellables)
        playback.progress.objectWillChange
            .sink { progressChanges += 1 }
            .store(in: &cancellables)

        playback.progress.setPosition(12)
        playback.progress.setDuration(180)

        XCTAssertEqual(playbackChanges, 0)
        XCTAssertEqual(progressChanges, 2)
    }

    func testBilibiliImportProgressOnlyPublishesItsOwnStore() {
        let playback = MusicPlaybackStore(source: .bilibili, volume: 0.8)
        let account = BilibiliAccountStore()
        let importer = BilibiliImportStore()
        var playbackChanges = 0
        var accountChanges = 0
        var importerChanges = 0
        playback.objectWillChange
            .sink { playbackChanges += 1 }
            .store(in: &cancellables)
        account.objectWillChange
            .sink { accountChanges += 1 }
            .store(in: &cancellables)
        importer.objectWillChange
            .sink { importerChanges += 1 }
            .store(in: &cancellables)

        for completed in 1...100 {
            importer.completedCount = completed
        }

        XCTAssertEqual(playbackChanges, 0)
        XCTAssertEqual(accountChanges, 0)
        XCTAssertEqual(importerChanges, 100)
    }

    func testBilibiliImportCannotCommitAfterShutdown() async {
        let provider = SuspendedBilibiliProvider()
        let importStore = BilibiliImportStore()
        let delegate = RecordingBilibiliCoordinatorDelegate()
        let coordinator = BilibiliMusicCoordinator(
            accountStore: BilibiliAccountStore(),
            importStore: importStore,
            bilibili: provider
        )
        coordinator.delegate = delegate
        importStore.input = "BV1shutdown"

        coordinator.importBilibili()
        await provider.waitUntilResolveStarted()

        let shutdown = Task { await coordinator.shutdown() }
        while !coordinator.tasks.isShuttingDown {
            await Task.yield()
        }
        await provider.resumeResolve(with: [makeBilibiliTrack(id: "late")])
        await shutdown.value

        XCTAssertEqual(delegate.importCallCount, 0)
        XCTAssertEqual(delegate.playCallCount, 0)
        XCTAssertFalse(importStore.isImporting)
        XCTAssertNil(importStore.importMessage)
        XCTAssertEqual(coordinator.tasks.activeTaskCount, 0)
    }

    func testShutdownAwaitsReplacedTaskThatIgnoresCancellation() async {
        let suspension = SuspendedOperations()
        let registry = MusicTaskRegistry()
        var committedValues: [Int] = []

        registry.launch(key: "replaceable") { generation in
            await suspension.suspend(id: 1)
            guard registry.isCurrent(generation) else { return }
            committedValues.append(1)
        }
        await suspension.waitUntilStarted(id: 1)

        registry.launch(key: "replaceable") { generation in
            await suspension.suspend(id: 2)
            guard registry.isCurrent(generation) else { return }
            committedValues.append(2)
        }
        await suspension.waitUntilStarted(id: 2)

        let shutdown = Task { await registry.shutdown() }
        while !registry.isShuttingDown {
            await Task.yield()
        }
        await suspension.resume(id: 1)
        await suspension.resume(id: 2)
        await shutdown.value

        XCTAssertTrue(committedValues.isEmpty)
        XCTAssertEqual(registry.activeTaskCount, 0)
    }

    func testLocalRelocationCannotCommitAfterShutdown() async {
        let importer = SuspendedLocalMusicImporter()
        let delegate = RecordingLocalCoordinatorDelegate()
        let coordinator = LocalMusicCoordinator(
            importStore: LocalMusicImportStore(),
            importer: importer,
            artworkRepository: NoopArtworkRepository(),
            fileRevealer: NoopFileRevealer()
        )
        coordinator.delegate = delegate
        let track = makeLocalTrack(id: "local:shutdown")

        coordinator.relocate(
            track,
            to: URL(fileURLWithPath: "/tmp/relocated.mp3")
        )
        await importer.waitUntilRelocationStarted()

        let shutdown = Task { await coordinator.shutdown() }
        while !coordinator.tasks.isShuttingDown {
            await Task.yield()
        }
        await importer.resumeRelocation(with: track)
        await shutdown.value

        XCTAssertEqual(delegate.replaceTrackCallCount, 0)
        XCTAssertEqual(delegate.persistCallCount, 0)
        XCTAssertEqual(coordinator.tasks.activeTaskCount, 0)
    }

    func testBilibiliFavoriteBatchDeduplicatesRepeatedTrackIDs() {
        let store = MusicLibraryStore()
        let controller = MusicLibraryController(
            store: store,
            persistence: MusicPersistenceCoordinator(library: NoopMusicLibrary())
        )
        let track = makeBilibiliTrack(id: "duplicate")

        let added = controller.importTracks([track, track, track], playlistName: "收藏夹")

        XCTAssertEqual(added.map(\.id), ["duplicate"])
        XCTAssertEqual(store.playlist.map(\.id), ["duplicate"])
        XCTAssertEqual(store.savedPlaylists.first?.trackIDs, ["duplicate"])
    }

    private func makeBilibiliTrack(id: String) -> MusicTrack {
        MusicTrack(
            id: id,
            source: .bilibili,
            title: id,
            artist: "Artist",
            album: nil,
            coverURL: nil,
            duration: 180,
            bilibili: nil,
            subtitleURL: nil
        )
    }

    private func makeLocalTrack(id: String) -> MusicTrack {
        MusicTrack(
            id: id,
            source: .local,
            title: id,
            artist: "Artist",
            album: nil,
            coverURL: nil,
            duration: 180,
            bilibili: nil,
            subtitleURL: nil,
            local: LocalTrackReference(
                bookmarkData: Data([1, 2, 3]),
                originalFilename: "track.mp3",
                fileSize: 10
            )
        )
    }
}

@MainActor
private final class RecordingBilibiliCoordinatorDelegate:
    BilibiliMusicCoordinatorDelegate {
    private(set) var importCallCount = 0
    private(set) var playCallCount = 0

    func importBilibiliTracks(
        _ tracks: [MusicTrack],
        playlistName: String?
    ) -> [MusicTrack] {
        importCallCount += 1
        return tracks
    }

    func bilibiliTrack(withID id: String) -> MusicTrack? { nil }

    func playBilibiliTrack(_ track: MusicTrack) {
        playCallCount += 1
    }

    func refreshCurrentBilibiliLyricsAfterLogin() async {}
}

private actor SuspendedBilibiliProvider: BilibiliMusicProviding {
    private var resolveContinuation: CheckedContinuation<[MusicTrack], Error>?

    func resolveTracks(from input: String) async throws -> [MusicTrack] {
        try await withCheckedThrowingContinuation { continuation in
            resolveContinuation = continuation
        }
    }

    func waitUntilResolveStarted() async {
        while resolveContinuation == nil {
            await Task.yield()
        }
    }

    func resumeResolve(with tracks: [MusicTrack]) {
        resolveContinuation?.resume(returning: tracks)
        resolveContinuation = nil
    }

    func audioLocation(for track: MusicTrack) async throws -> BilibiliAudioLocation {
        BilibiliAudioLocation(candidates: [])
    }

    func subtitleURL(for track: MusicTrack) async -> URL? { nil }
    func playbackHeaders() async -> [String: String] { [:] }
}

private actor SuspendedOperations {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func suspend(id: Int) async {
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
    }

    func waitUntilStarted(id: Int) async {
        while continuations[id] == nil {
            await Task.yield()
        }
    }

    func resume(id: Int) {
        continuations.removeValue(forKey: id)?.resume()
    }
}

@MainActor
private final class RecordingLocalCoordinatorDelegate: LocalMusicCoordinatorDelegate {
    private(set) var replaceTrackCallCount = 0
    private(set) var persistCallCount = 0

    var localDuplicateKeys: Set<String> { [] }
    var referencedArtworkKeys: Set<String> { [] }
    func appendImportedLocalTracks(_ tracks: [MusicTrack]) {}
    func didImportLocalTracks() {}

    func replaceLocalTrack(_ original: MusicTrack, with updated: MusicTrack) -> Bool {
        replaceTrackCallCount += 1
        return true
    }

    func didRelocateCurrentLocalTrack(_ original: MusicTrack, to updated: MusicTrack) {}

    func replaceArtwork(
        for trackID: String,
        with newKey: String
    ) -> (didReplace: Bool, previousKey: String?) {
        (false, nil)
    }

    func removeArtwork(for trackID: String) -> String? { nil }

    func persistLocalMusicChanges() {
        persistCallCount += 1
    }
}

private actor SuspendedLocalMusicImporter: LocalMusicImporting {
    private var relocationContinuation: CheckedContinuation<MusicTrack, Error>?

    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult {
        LocalMusicImportResult(tracks: [], failures: [])
    }

    func resolveURL(for track: MusicTrack) async throws -> URL {
        URL(fileURLWithPath: "/tmp/track.mp3")
    }

    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack {
        try await withCheckedThrowingContinuation { continuation in
            relocationContinuation = continuation
        }
    }

    func waitUntilRelocationStarted() async {
        while relocationContinuation == nil {
            await Task.yield()
        }
    }

    func resumeRelocation(with track: MusicTrack) {
        relocationContinuation?.resume(returning: track)
        relocationContinuation = nil
    }

    func localLyrics(for track: MusicTrack) async throws -> LyricsDocument? { nil }
}

private actor NoopArtworkRepository: LocalMusicArtworkManaging {
    func store(_ data: Data, key: String) async throws {}
    func importArtwork(from url: URL) async throws -> String { "artwork" }
    func data(for track: MusicTrack) async -> Data? { nil }
    func remove(keys: Set<String>) async {}
    func removeOrphans(keeping keys: Set<String>) async {}
}

@MainActor
private final class NoopFileRevealer: LocalMusicFileRevealing {
    func reveal(_ url: URL) {}
}

private actor NoopMusicLibrary: MusicLibraryCoordinating {
    func load() async throws -> MusicLibrarySnapshot { MusicLibrarySnapshot() }
    func scheduleSave(_ snapshot: MusicLibrarySnapshot, revision: UInt64) async {}
    func saveNow(_ snapshot: MusicLibrarySnapshot, revision: UInt64) async {}
}
