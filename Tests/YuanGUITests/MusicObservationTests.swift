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

    func testProductionSourcesDoNotReintroduceObservedMusicFeature() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = repository.appending(path: "Sources/YuanGUI")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        ))
        var offenders: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            if contents.contains("@ObservedMusicFeature")
                || contents.contains("struct ObservedMusicFeature") {
                offenders.append(url.path.replacingOccurrences(of: repository.path + "/", with: ""))
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Wide music observation returned in: \(offenders)")
    }

    func testMusicFeatureRemainsACompactNonObservableFacade() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let featureURL = repository.appending(path: "Sources/YuanGUI/Stores/MusicFeature.swift")
        let contents = try String(contentsOf: featureURL, encoding: .utf8)
        let lineCount = contents.split(separator: "\n", omittingEmptySubsequences: false).count

        XCTAssertLessThanOrEqual(lineCount, 500)
        XCTAssertFalse(contents.contains("ObservableObject"))
        XCTAssertFalse(contents.contains("@Published"))
    }

    func testMusicRuntimeGodObjectCannotReturn() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stores = repository.appending(path: "Sources/YuanGUI/Stores")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: stores,
            includingPropertiesForKeys: nil
        ))
        var offenders: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            if contents.contains("MusicFeatureRuntime")
                || contents.contains("unowned let runtime")
                || contents.contains("runtime.") {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertTrue(offenders.isEmpty, "Central music runtime returned in: \(offenders)")
    }

    func testMusicContextOnlyComposesStoresAndCoordinatorReferences() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contextURL = repository.appending(
            path: "Sources/YuanGUI/Stores/MusicFeatureContext.swift"
        )
        let contents = try String(contentsOf: contextURL, encoding: .utf8)

        XCTAssertFalse(contents.contains("Task<"))
        XCTAssertFalse(contents.contains("URLMusicPlaying"))
        XCTAssertFalse(contents.contains("MusicPlaybackQueue"))
        XCTAssertFalse(contents.contains("lyricsByTrackID"))
        XCTAssertFalse(contents.contains("Providing"))
    }

    func testDomainCoordinatorsOwnTheirAsyncState() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stores = repository.appending(path: "Sources/YuanGUI/Stores")
        let expectations: [(String, [String])] = [
            (
                "MusicPlaybackCoordinator.swift",
                ["urlPlayer:", "appleSyncTask:", "musicPlaybackQueue"]
            ),
            (
                "MusicLyricsCoordinator.swift",
                ["lyricLoadTask:", "lyricsSearchTask:", "lyricsByTrackID:"]
            ),
            (
                "BilibiliMusicCoordinator.swift",
                ["loginTask:", "favoriteTask:", "lastImportedTrackID:"]
            ),
            (
                "LocalMusicCoordinator.swift",
                ["importTask:", "artworkMaintenanceTask:"]
            ),
            (
                "MusicLibraryController.swift",
                ["libraryRestoreTask:", "MusicPersistenceCoordinator"]
            )
        ]

        for (filename, requiredTokens) in expectations {
            let contents = try String(
                contentsOf: stores.appending(path: filename),
                encoding: .utf8
            )
            for token in requiredTokens {
                XCTAssertTrue(
                    contents.contains(token),
                    "\(filename) does not own \(token)"
                )
            }
        }
    }

    func testHighFrequencyMusicViewsUseNarrowObservationBoundaries() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let playbackViews = try String(
            contentsOf: repository.appending(path: "Sources/YuanGUI/Views/MusicPlaybackViews.swift"),
            encoding: .utf8
        )
        let progressBlock = try XCTUnwrap(
            playbackViews.components(separatedBy: "struct MusicProgressView: View").last?
                .components(separatedBy: "struct MusicVolumeControl: View").first
        )
        let petRoot = try String(
            contentsOf: repository.appending(path: "Sources/YuanGUI/Views/PetRootView.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repository.appending(path: "Sources/YuanGUI/Views/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(progressBlock.contains("MusicPlaybackProgress"))
        XCTAssertFalse(progressBlock.contains("MusicPlaybackStore"))
        XCTAssertFalse(progressBlock.contains("LyricsStore"))
        XCTAssertFalse(petRoot.contains("@ObservedObject private var lyrics: LyricsStore"))
        XCTAssertFalse(settings.contains("@ObservedObject private var lyrics: LyricsStore"))
    }
}
