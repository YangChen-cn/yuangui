import Foundation
import XCTest
@testable import YuanGUI

final class MusicTests: XCTestCase {
    func testMusicLibraryQuerySearchesMetadataAndFilenameAndSortsStably() {
        var first = makeLocalTrack(id: "local:first", filename: "Café Song.mp3")
        first.title = "晨光"
        first.artist = "Artist B"
        first.album = "Album"
        first.duration = 240
        var second = makeLocalTrack(id: "local:second", filename: "other.m4a")
        second.title = "Echo"
        second.artist = "Artist A"
        second.album = "Album"
        second.duration = 120
        var third = makeLocalTrack(id: "local:third", filename: "third.aac")
        third.title = "Echo"
        third.artist = "Artist A"
        third.album = "Album"
        third.duration = 180

        XCTAssertEqual(
            MusicLibraryQuery(searchText: "CAFÉ").apply(to: [first, second, third]).map(\.id),
            [first.id]
        )
        XCTAssertEqual(
            MusicLibraryQuery(searchText: "晨光").apply(to: [first, second, third]).map(\.id),
            [first.id]
        )

        let ascending = MusicLibraryQuery(
            sortField: .artist,
            sortDirection: .ascending
        ).apply(to: [first, second, third])
        XCTAssertEqual(ascending.map(\.id), [second.id, third.id, first.id])

        let descending = MusicLibraryQuery(
            sortField: .duration,
            sortDirection: .descending
        ).apply(to: [first, second, third])
        XCTAssertEqual(descending.map(\.id), [first.id, third.id, second.id])
    }

    func testArtworkRepositoryPrunesOnlyUnreferencedCacheFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ArtworkRepository-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalMusicArtworkRepository(rootURL: root)
        try await repository.store(Data([1]), key: "keep.artwork")
        try await repository.store(Data([2]), key: "orphan.artwork")

        await repository.removeOrphans(keeping: ["keep.artwork"])

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "keep.artwork").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "orphan.artwork").path))

        await repository.remove(keys: ["../keep.artwork", "keep.artwork"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "keep.artwork").path))
    }

    func testArtworkRepositoryImportsAValidatedImage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ArtworkImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appending(path: "cover.png")
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        try imageData.write(to: imageURL)
        let cacheRoot = root.appending(path: "Cache", directoryHint: .isDirectory)
        let repository = LocalMusicArtworkRepository(rootURL: cacheRoot)

        let key = try await repository.importArtwork(from: imageURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheRoot.appending(path: key).path))
        var bilibiliTrack = MusicTrack(
            id: "bilibili:custom-cover",
            source: .bilibili,
            title: "Song",
            artist: "Artist",
            duration: 120
        )
        bilibiliTrack.localArtworkCacheKey = key
        let cachedData = await repository.data(for: bilibiliTrack)
        XCTAssertEqual(cachedData, imageData)
    }

    func testLocalRelocationRefreshesMetadataAndArtwork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RelocationArtwork-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = FileManager.default.temporaryDirectory
            .appending(path: "relocated-\(UUID().uuidString).mp3")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: file)
        }
        try Data([0]).write(to: file)
        let repository = LocalMusicArtworkRepository(rootURL: root)
        let service = LocalMusicImportService(
            artworkRepository: repository,
            metadataReader: StubLocalMusicMetadataReader(metadata: LocalMusicMetadata(
                title: "New Title",
                artist: "New Artist",
                album: "New Album",
                duration: 321,
                artworkData: Data([9, 8, 7])
            ))
        )

        let updated = try await service.relocatedTrack(
            makeLocalTrack(id: "local:relocated", filename: "old.mp3"),
            to: file
        )

        XCTAssertEqual(updated.id, "local:relocated")
        XCTAssertEqual(updated.title, "New Title")
        XCTAssertEqual(updated.artist, "New Artist")
        XCTAssertEqual(updated.album, "New Album")
        XCTAssertEqual(updated.duration, 321)
        XCTAssertEqual(updated.local?.originalFilename, file.lastPathComponent)
        let key = try XCTUnwrap(updated.localArtworkCacheKey)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: key)), Data([9, 8, 7]))

        let noArtworkService = LocalMusicImportService(
            artworkRepository: repository,
            metadataReader: StubLocalMusicMetadataReader(metadata: LocalMusicMetadata(
                title: nil,
                artist: nil,
                album: nil,
                duration: 111,
                artworkData: nil
            ))
        )
        let withoutArtwork = try await noArtworkService.relocatedTrack(
            makeLocalTrack(
                id: "local:no-artwork",
                filename: "old.mp3",
                artworkKey: "old.artwork"
            ),
            to: file
        )
        XCTAssertEqual(withoutArtwork.title, file.deletingPathExtension().lastPathComponent)
        XCTAssertNil(withoutArtwork.localArtworkCacheKey)
    }

    @MainActor
    func testDesktopLyricsBackgroundOpacityDefaultsClampsAndPersists() {
        let suite = "LyricsOpacityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LyricsPresentationStore(defaults: defaults)
        XCTAssertEqual(store.backgroundOpacity, 0.24, accuracy: 0.001)

        defaults.set(0.90, forKey: "musicLyricsBackgroundOpacity")
        XCTAssertEqual(
            LyricsPresentationStore(defaults: defaults).backgroundOpacity,
            0.60,
            accuracy: 0.001
        )

        defaults.set(0.05, forKey: "musicLyricsBackgroundOpacity")
        XCTAssertEqual(
            LyricsPresentationStore(defaults: defaults).backgroundOpacity,
            0.12,
            accuracy: 0.001
        )
    }

    @MainActor
    func testDesktopLyricsVisibilityRestoresFromDefaults() {
        let suite = "LyricsVisibilityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "musicLyricsVisible")

        XCTAssertTrue(LyricsPresentationStore(defaults: defaults).isVisible)
    }

    @MainActor
    func testDesktopLyricsFontChoiceRestoresWithoutLanguageMigration() {
        let suite = "LyricsFontTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(LyricsFontStyle.pingFang.rawValue, forKey: "musicLyricsFontStyle")

        XCTAssertEqual(LyricsPresentationStore(defaults: defaults).fontStyle, .pingFang)
    }

    @MainActor
    func testLyricsChineseConversionModeDefaultsAndRestores() {
        let suite = "LyricsChineseConversionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            LyricsPresentationStore(defaults: defaults).chineseConversionMode,
            .automatic
        )

        defaults.set(
            LyricsChineseConversionMode.traditional.rawValue,
            forKey: "musicLyricsChineseConversion"
        )
        XCTAssertEqual(
            LyricsPresentationStore(defaults: defaults).chineseConversionMode,
            .traditional
        )
    }

    @MainActor
    func testLiveBilibiliPublicAudioStartsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["YUANGUI_LIVE_BILI"] == "1" else {
            throw XCTSkip("Set YUANGUI_LIVE_BILI=1 to run the network integration test")
        }
        let client = BilibiliClient()
        let tracks = try await client.resolveTracks(from: "BV19p4y187Kk")
        let track = try XCTUnwrap(tracks.first)
        let location = try await client.audioLocation(for: track)
        let headers = await client.playbackHeaders()
        let player = URLMusicPlayerEngine()
        let started = expectation(description: "Bilibili audio starts")
        var playbackError: Error?
        player.onStateChange = { state in
            if state == .playing { started.fulfill() }
        }
        player.onFailure = { error in
            playbackError = error
            started.fulfill()
        }
        player.load(urls: location.candidates, headers: headers)
        await fulfillment(of: [started], timeout: 20)
        player.stop()
        XCTAssertNil(playbackError)
    }

    func testLiveBilibiliSubtitleConsensusForReportedVideosWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["YUANGUI_LIVE_BILI_SUBTITLES"] == "1" else {
            throw XCTSkip("Set YUANGUI_LIVE_BILI_SUBTITLES=1 to run the subtitle integration test")
        }
        let accountService = BilibiliAccountService()
        guard try await accountService.currentAccount() != nil else {
            throw XCTSkip("A persisted Bilibili login is required")
        }
        let client = BilibiliClient()
        let expectedSubtitlePathMarkers = [
            "BV1Sy4y1m7Uk": "798237972266999608",
            "BV1Bf4y1q78f": "287820372256861889",
            "BV19p4y187Kk": "134b1bcefa60c47718f3a2214ecd4818fc7037bf"
        ]

        for _ in 0..<3 {
            for (bvid, marker) in expectedSubtitlePathMarkers {
                let tracks = try await client.resolveTracks(from: bvid)
                let track = try XCTUnwrap(tracks.first)
                let reference = try XCTUnwrap(track.bilibili)
                let resolvedSubtitleURL = await client.subtitleURL(for: track)
                let subtitleURL = try XCTUnwrap(resolvedSubtitleURL)
                XCTAssertEqual(reference.bvid, bvid)
                XCTAssertTrue(
                    subtitleURL.path.contains(marker),
                    "\(bvid) returned unrelated subtitle URL: \(subtitleURL.path)"
                )
                let lyrics = await LyricsService().lyrics(for: track)
                XCTAssertEqual(lyrics?.source, "Bilibili 字幕")
                XCTAssertFalse(lyrics?.lines.isEmpty ?? true)
            }
        }
    }

    func testBilibiliInputParserAcceptsBVAndTrustedVideoURLs() {
        XCTAssertEqual(BilibiliInputParser.extractBVID(from: "BV1xx411c7mD"), "BV1xx411c7mD")
        XCTAssertEqual(
            BilibiliInputParser.extractBVID(from: "https://www.bilibili.com/video/BV1xx411c7mD?p=2"),
            "BV1xx411c7mD"
        )
        XCTAssertTrue(BilibiliInputParser.isTrustedVideoURL(URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!))
        XCTAssertFalse(BilibiliInputParser.isTrustedVideoURL(URL(string: "https://bilibili.com.evil.example/video/BV1xx411c7mD")!))
        XCTAssertFalse(BilibiliInputParser.isTrustedVideoURL(URL(string: "http://www.bilibili.com/video/BV1xx411c7mD")!))
    }

    func testLRCParserSupportsMultipleTimestampsFractionsAndOffset() {
        let document = LyricsParser.parseLRC("""
        [ti:测试歌曲]
        [ar:测试歌手]
        [offset:500]
        [00:01.20][00:03.250]第一句
        [00:05.00]第二句
        """)
        XCTAssertEqual(document.title, "测试歌曲")
        XCTAssertEqual(document.artist, "测试歌手")
        XCTAssertEqual(document.lines.count, 3)
        XCTAssertEqual(document.lines[0].time, 1.7, accuracy: 0.001)
        XCTAssertEqual(document.lines[1].time, 3.75, accuracy: 0.001)
        XCTAssertEqual(document.line(at: 4)?.text, "第一句")
        XCTAssertEqual(document.nextLine(after: 4)?.text, "第二句")
    }

    func testLyricsDetectionSampleContainsOnlyLyricText() {
        let sample = LyricsParser.detectionSample(fromLRC: """
        [ti:測試歌曲]
        [ar:測試歌手]
        [00:10.00]我願意為你
        [00:15.20][00:16.00]忘記我姓名
        """)

        XCTAssertEqual(sample, "我願意為你\n忘記我姓名")
        XCTAssertFalse(sample.contains("00:10"))
        XCTAssertFalse(sample.contains("測試歌手"))
    }

    func testLyricsChineseDisplayConversionModes() {
        let traditionalDocument = LyricsParser.parseLRC("""
        [00:01.00]我願意為你忘記姓名
        [00:02.00]這是一首繁體中文歌曲
        [00:03.00]讓我們繼續聽音樂
        """)
        var converter = LyricsChineseDisplayConverter()
        converter.prepare(document: traditionalDocument)

        XCTAssertEqual(
            converter.displayedText(
                "我願意為你",
                mode: .automatic,
                preferredLanguages: ["zh-Hans-CN"]
            ),
            "我愿意为你"
        )
        XCTAssertEqual(
            converter.displayedText("我願意為你", mode: .unchanged),
            "我願意為你"
        )

        let simplifiedDocument = LyricsParser.parseLRC("""
        [00:01.00]我愿意为你忘记姓名
        [00:02.00]这是一首简体中文歌曲
        [00:03.00]让我们继续听音乐
        """)
        converter.prepare(document: simplifiedDocument)
        XCTAssertEqual(
            converter.displayedText("我愿意为你", mode: .traditional),
            "我願意為你"
        )
    }

    func testLyricsAutomaticChineseTargetUsesSystemLanguageScript() {
        XCTAssertEqual(
            LyricsChineseDisplayConverter.targetScript(
                for: .automatic,
                preferredLanguages: ["zh-Hans-CN"]
            ),
            .simplified
        )
        XCTAssertEqual(
            LyricsChineseDisplayConverter.targetScript(
                for: .automatic,
                preferredLanguages: ["zh-Hant-TW"]
            ),
            .traditional
        )
        XCTAssertEqual(
            LyricsChineseDisplayConverter.targetScript(
                for: .automatic,
                preferredLanguages: ["en-US"]
            ),
            .unchanged
        )
    }

    func testLyricsDocumentNavigationScenarios() {
        runLyricsDocumentBinarySearchHandlesBoundariesAndDuplicateTimestamps()
        runLyricsDocumentBuildsStableSevenSlotWindows()
        runLyricsDocumentBinarySearchHandlesLongDocuments()
        runLyricSeekPositionAppliesOffsetAndClampsToTrackBounds()
    }

    private func runLyricsDocumentBinarySearchHandlesBoundariesAndDuplicateTimestamps() {
        let document = LyricsDocument(
            title: nil,
            artist: nil,
            lines: [
                TimedLyricLine(time: 1, text: "第一句"),
                TimedLyricLine(time: 2, text: "同时间 A"),
                TimedLyricLine(time: 2, text: "同时间 B"),
                TimedLyricLine(time: 4, text: "最后一句")
            ],
            source: "测试"
        )

        XCTAssertNil(document.lineIndex(at: 0.99))
        XCTAssertEqual(document.lineIndex(at: 1), 0)
        XCTAssertEqual(document.lineIndex(at: 2), 2)
        XCTAssertEqual(document.lineIndex(at: 3.99), 2)
        XCTAssertEqual(document.lineIndex(at: 20), 3)
        XCTAssertEqual(document.line(at: 2)?.text, "同时间 B")
        XCTAssertEqual(document.nextLine(after: 2)?.text, "最后一句")
    }

    private func runLyricsDocumentBuildsStableSevenSlotWindows() {
        let document = LyricsDocument(
            title: nil,
            artist: nil,
            lines: (0..<5).map { TimedLyricLine(time: Double($0), text: "第\($0)句") },
            source: "测试"
        )

        XCTAssertEqual(document.lineIndices(around: 0), [nil, nil, nil, 0, 1, 2, 3])
        XCTAssertEqual(document.lineIndices(around: 2), [nil, 0, 1, 2, 3, 4, nil])
        XCTAssertEqual(document.lineIndices(around: 4), [1, 2, 3, 4, nil, nil, nil])
        XCTAssertEqual(document.lineIndices(around: nil), [nil, nil, nil, 0, 1, 2, 3])
    }

    private func runLyricsDocumentBinarySearchHandlesLongDocuments() {
        let document = LyricsDocument(
            title: nil,
            artist: nil,
            lines: (0..<10_000).map {
                TimedLyricLine(time: Double($0) * 0.25, text: "第\($0)句")
            },
            source: "测试"
        )

        XCTAssertEqual(document.lineIndex(at: 1_234.24), 4_936)
        XCTAssertEqual(document.lineIndex(at: 2_499.75), 9_999)
    }

    private func runLyricSeekPositionAppliesOffsetAndClampsToTrackBounds() {
        let line = TimedLyricLine(time: 10, text: "目标歌词")
        XCTAssertEqual(MusicFeature.lyricSeekPosition(for: line, offset: 1.5, duration: 30), 11.5)
        XCTAssertEqual(MusicFeature.lyricSeekPosition(for: line, offset: -12, duration: 30), 0)
        XCTAssertEqual(MusicFeature.lyricSeekPosition(for: line, offset: 25, duration: 30), 30)
        XCTAssertEqual(MusicFeature.lyricSeekPosition(for: line, offset: 2, duration: 0), 12)
    }

    func testMusicLibraryFileStoreRoundTripsWithoutTemporaryStreamURLs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library.json")
        let store = MusicLibraryFileStore(fileURL: file)
        let track = MusicTrack(
            id: "bili:BV1xx411c7mD:42", source: .bilibili, title: "测试", artist: "UP主",
            album: "P1", coverURL: URL(string: "https://i0.hdslb.com/test.jpg"), duration: 120,
            bilibili: BilibiliTrackReference(bvid: "BV1xx411c7mD", aid: 1, cid: 42, page: 1), subtitleURL: nil
        )
        let savedPlaylist = SavedMusicPlaylist(name: "通勤", trackIDs: [track.id])
        let cachedLyrics = LyricsParser.parseLRC("[00:01.00]缓存歌词", source: "LRCLIB")
        let snapshot = MusicLibrarySnapshot(
            playlist: [track], playMode: .repeatAll, currentTrackID: track.id, lastPosition: 33,
            favoriteTrackIDs: [track.id], savedPlaylists: [savedPlaylist], lyricOffsets: [track.id: 1.4],
            lyricsByTrackID: [track.id: cachedLyrics]
        )
        try store.save(snapshot)
        let loaded = try store.load()
        XCTAssertEqual(loaded.playlist, [track])
        XCTAssertEqual(loaded.playMode, .repeatAll)
        XCTAssertEqual(loaded.currentTrackID, track.id)
        XCTAssertEqual(loaded.lastPosition, 33)
        XCTAssertEqual(loaded.favoriteTrackIDs, [track.id])
        XCTAssertEqual(loaded.savedPlaylists, [savedPlaylist])
        XCTAssertEqual(loaded.lyricOffsets[track.id], 1.4)
        XCTAssertEqual(loaded.lyricsByTrackID[track.id], cachedLyrics)
        XCTAssertFalse(String(data: try Data(contentsOf: file), encoding: .utf8)!.contains("baseUrl"))
    }

    func testMusicLibrarySnapshotDecodesLegacyLibraryWithoutCollections() throws {
        let legacy = Data(#"{"playlist":[],"playMode":"sequential","lastPosition":12}"#.utf8)
        let snapshot = try JSONDecoder().decode(MusicLibrarySnapshot.self, from: legacy)
        XCTAssertTrue(snapshot.favoriteTrackIDs.isEmpty)
        XCTAssertTrue(snapshot.savedPlaylists.isEmpty)
        XCTAssertTrue(snapshot.lyricOffsets.isEmpty)
        XCTAssertTrue(snapshot.lyricsByTrackID.isEmpty)
        XCTAssertEqual(snapshot.lastPosition, 12)
    }

    func testLocalTrackReferenceRoundTripsAndLegacyTrackStillDecodes() throws {
        let reference = LocalTrackReference(
            bookmarkData: Data([1, 2, 3]),
            originalFilename: "Song.m4a",
            fileSize: 42
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                LocalTrackReference.self,
                from: JSONEncoder().encode(reference)
            ),
            reference
        )

        let legacy = Data(
            #"{"id":"old","source":"bilibili","title":"Old","artist":"Artist","duration":120}"#.utf8
        )
        let track = try JSONDecoder().decode(MusicTrack.self, from: legacy)
        XCTAssertNil(track.local)
        XCTAssertNil(track.localArtworkCacheKey)
        XCTAssertEqual(
            LocalMusicImportService.supportedExtensions,
            Set(["mp3", "m4a", "aac", "wav", "aiff"])
        )
    }

    func testAppleMusicLyricsCacheKeyIgnoresDurationAndMetadataFormatting() {
        let first = MusicTrack.appleMusic(
            title: "Café  Song", artist: "The Artist", album: nil, duration: 199.99
        )
        let refreshed = MusicTrack.appleMusic(
            title: "cafe song", artist: "the  artist", album: nil, duration: 200.01
        )

        XCTAssertNotEqual(first.id, refreshed.id)
        XCTAssertEqual(first.lyricsCacheKey, refreshed.lyricsCacheKey)
        let durationOnlyRefresh = MusicTrack.appleMusic(
            title: "Café  Song", artist: "The Artist", album: nil, duration: 200.01
        )
        XCTAssertTrue(durationOnlyRefresh.matchesLegacyLyricsCacheKey(first.id))
    }

    func testLyricsServiceScenarios() async throws {
        try await runLyricsServiceMatchesByTitleWhenArtistIsEmptyAndSetsTimeout()
        try await runLyricsServiceReportsTimeout()
        try await runLyricsServiceAcceptsCandidatesWithMissingDuration()
        try await runLyricsServiceAcceptsSwappedTrackAndArtistFields()
        try await runLyricsServiceFallsBackToTitleOnlyForAppleMusicAndLocalTracks()
        try await runLyricsServiceDoesNotRunSlowBroadFallbackAfterExactMiss()
    }

    private func runLyricsServiceAcceptsCandidatesWithMissingDuration() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = Data(#"""
            [
                {"trackName":"We Belong Together","artistName":"Mariah Carey","duration":null,"syncedLyrics":"[00:01.00]Null duration remains usable"},
                {"trackName":"We Belong Together","artistName":"Mariah Carey","duration":201,"syncedLyrics":"[00:01.00]Exact duration wins"}
            ]
            """#.utf8)
            return (response, data)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = LyricsService(session: session)
        let document = try await service.search(
            title: "We Belong Together",
            artist: "Mariah Carey",
            duration: 201
        )

        XCTAssertEqual(document?.lines.first?.text, "Exact duration wins")
    }

    private func runLyricsServiceMatchesByTitleWhenArtistIsEmptyAndSetsTimeout() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var capturedRequest: URLRequest?
        LyricsURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = Data(#"[{"trackName":"测试歌曲","artistName":"测试歌手","duration":120,"syncedLyrics":"[00:01.00]第一句"}]"#.utf8)
            return (response, data)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = LyricsService(session: session)
        let document = try await service.search(title: "测试歌曲", artist: "", duration: 120)

        XCTAssertEqual(document?.lines.first?.text, "第一句")
        XCTAssertEqual(capturedRequest?.timeoutInterval, 30)
        let items = URLComponents(url: try XCTUnwrap(capturedRequest?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "track_name" })?.value, "测试歌曲")
        XCTAssertNil(items?.first(where: { $0.name == "artist_name" }))
    }

    private func runLyricsServiceReportsTimeout() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = LyricsService(session: session, requestTimeout: 0.25)
        do {
            _ = try await service.search(title: "测试歌曲", artist: "测试歌手", duration: 120)
            XCTFail("Expected timeout")
        } catch let error as LyricsServiceError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    private func runLyricsServiceAcceptsSwappedTrackAndArtistFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var queries: [(title: String?, artist: String?)] = []
        LyricsURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            let title = items?.first(where: { $0.name == "track_name" })?.value
            let artist = items?.first(where: { $0.name == "artist_name" })?.value
            queries.append((title, artist))
            guard title == "讨厌红楼梦", artist == "陶喆" else {
                return (response, Data("[]".utf8))
            }
            let data = Data(#"[{"trackName":"讨厌红楼梦","artistName":"陶喆","duration":235,"syncedLyrics":"[00:01.00]交换字段也能匹配"}]"#.utf8)
            return (response, data)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = LyricsService(session: session)
        let document = try await service.search(title: "陶喆", artist: "讨厌红楼梦", duration: 235)

        XCTAssertEqual(document?.lines.first?.text, "交换字段也能匹配")
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(queries[0].title, "陶喆")
        XCTAssertEqual(queries[0].artist, "讨厌红楼梦")
        XCTAssertEqual(queries[1].title, "讨厌红楼梦")
        XCTAssertEqual(queries[1].artist, "陶喆")
    }

    private func runLyricsServiceFallsBackToTitleOnlyForAppleMusicAndLocalTracks() async throws {
        for source in [MusicSource.appleMusic, .local] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [LyricsURLProtocol.self]
            let session = URLSession(configuration: configuration)
            var queries: [(title: String?, artist: String?)] = []
            LyricsURLProtocol.handler = { request in
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
                let title = items?.first(where: { $0.name == "track_name" })?.value
                let artist = items?.first(where: { $0.name == "artist_name" })?.value
                queries.append((title, artist))
                guard artist == nil else { return (response, Data("[]".utf8)) }
                let data = Data(#"[{"trackName":"目标歌曲","artistName":"","duration":null,"syncedLyrics":"[00:01.00]纯歌名也能找到"}]"#.utf8)
                return (response, data)
            }
            defer {
                LyricsURLProtocol.handler = nil
                session.invalidateAndCancel()
            }

            let service = LyricsService(session: session)
            let track = MusicTrack(
                id: "\(source.rawValue)-title-only",
                source: source,
                title: "目标歌曲",
                artist: "播放器歌手",
                album: nil,
                coverURL: nil,
                duration: 200,
                bilibili: nil,
                subtitleURL: nil
            )
            let document = await service.lyrics(for: track)

            XCTAssertEqual(document?.lines.first?.text, "纯歌名也能找到")
            XCTAssertEqual(queries.count, 3)
            XCTAssertEqual(queries[0].title, "目标歌曲")
            XCTAssertEqual(queries[0].artist, "播放器歌手")
            XCTAssertEqual(queries[1].title, "播放器歌手")
            XCTAssertEqual(queries[1].artist, "目标歌曲")
            XCTAssertEqual(queries[2].title, "目标歌曲")
            XCTAssertNil(queries[2].artist)
        }
    }

    private func runLyricsServiceDoesNotRunSlowBroadFallbackAfterExactMiss() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestCount = 0
        LyricsURLProtocol.handler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("[]".utf8))
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = LyricsService(session: session)
        let document = try await service.search(title: "测试歌曲", artist: "测试歌手", duration: 120)

        XCTAssertNil(document)
        XCTAssertEqual(requestCount, 2)
    }

    func testMusicLibraryActorFlushesLatestRevisionImmediately() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MusicLibraryFileStore(fileURL: directory.appendingPathComponent("library.json"))
        let library = MusicLibraryActor(store: store)
        let old = MusicLibrarySnapshot(lastPosition: 10)
        let latest = MusicLibrarySnapshot(lastPosition: 42)

        await library.scheduleSave(latest, revision: 2)
        await library.scheduleSave(old, revision: 1)
        await library.saveNow(latest, revision: 3)

        XCTAssertEqual(try store.load().lastPosition, 42)
    }

    func testBilibiliSubtitleIdentityScenarios() async throws {
        try await runBilibiliClientFallsBackToPlayerSubtitleURL()
        try await runBilibiliClientUsesEachPagesExactCIDInsteadOfViewSubtitle()
        try await runBilibiliClientRejectsSubtitleResponseForAnotherCID()
        try await runBilibiliClientRejectsRandomAISubtitleUntilURLMatchesCID()
        try await runBilibiliClientRequiresRepeatedIdentityForHumanSubtitle()
    }

    private func runBilibiliClientFallsBackToPlayerSubtitleURL() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/x/frontend/finger/spi_v2" { throw URLError(.badServerResponse) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path == "/x/web-interface/view" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1Bt4y1Y71r","aid":628037055,"title":"讨厌红楼梦","pic":"https://i0.hdslb.com/cover.jpg","owner":{"name":"The3heep"},"pages":[{"cid":263250978,"page":1,"part":"讨厌红楼梦","duration":235,"first_frame":null}],"subtitle":{"list":[{"subtitle_url":""}]}}}"#.utf8)
                return (response, data)
            }
            if url.path == "/x/player/v2" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1Bt4y1Y71r","cid":263250978,"subtitle":{"subtitles":[{"subtitle_url":"//aisubtitle.hdslb.com/test.json"}]}}}"#.utf8)
                return (response, data)
            }
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let client = BilibiliClient(session: session)
        let tracks = try await client.resolveTracks(from: "BV1Bt4y1Y71r")
        let track = try XCTUnwrap(tracks.first)
        let subtitleURL = await client.subtitleURL(for: track)

        XCTAssertNil(track.subtitleURL)
        XCTAssertEqual(
            subtitleURL?.absoluteString,
            "https://aisubtitle.hdslb.com/test.json"
        )
    }

    private func runBilibiliClientUsesEachPagesExactCIDInsteadOfViewSubtitle() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestedCIDs: [String] = []
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/x/frontend/finger/spi_v2" { throw URLError(.badServerResponse) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path == "/x/web-interface/view" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1Bt4y1Y71r","aid":628037055,"title":"测试合集","pic":"https://i0.hdslb.com/cover.jpg","owner":{"name":"UP主"},"pages":[{"cid":101,"page":1,"part":"P1","duration":60,"first_frame":null},{"cid":202,"page":2,"part":"P2","duration":70,"first_frame":null}],"subtitle":{"list":[{"subtitle_url":"//aisubtitle.hdslb.com/wrong-shared.json"}]}}}"#.utf8)
                return (response, data)
            }
            if url.path == "/x/player/v2" {
                let cid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "cid" })?.value ?? ""
                requestedCIDs.append(cid)
                let data = Data("{\"code\":0,\"message\":\"0\",\"data\":{\"bvid\":\"BV1Bt4y1Y71r\",\"cid\":\(cid),\"subtitle\":{\"subtitles\":[{\"id_str\":\"sub-\(cid)\",\"lan\":\"ai-zh\",\"subtitle_url\":\"//aisubtitle.hdslb.com/628037055-cid-\(cid).json\"}]}}}".utf8)
                return (response, data)
            }
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let client = BilibiliClient(session: session)
        let tracks = try await client.resolveTracks(from: "BV1Bt4y1Y71r")

        XCTAssertEqual(requestedCIDs, [])
        XCTAssertTrue(tracks.allSatisfy { $0.subtitleURL == nil })
        var subtitleURLs: [URL?] = []
        for track in tracks {
            subtitleURLs.append(await client.subtitleURL(for: track))
        }
        XCTAssertEqual(requestedCIDs, ["101", "202"])
        XCTAssertEqual(
            subtitleURLs.compactMap { $0?.lastPathComponent },
            ["628037055-cid-101.json", "628037055-cid-202.json"]
        )
    }

    private func runBilibiliClientRejectsSubtitleResponseForAnotherCID() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/x/frontend/finger/spi_v2" { throw URLError(.badServerResponse) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path == "/x/web-interface/view" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1Bt4y1Y71r","aid":628037055,"title":"当前视频","pic":"https://i0.hdslb.com/cover.jpg","owner":{"name":"UP主"},"pages":[{"cid":202,"page":1,"part":"P1","duration":60,"first_frame":null}]}}"#.utf8)
                return (response, data)
            }
            if url.path == "/x/player/v2" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1OtherVideo","cid":101,"subtitle":{"subtitles":[{"subtitle_url":"//aisubtitle.hdslb.com/wrong.json"}]}}}"#.utf8)
                return (response, data)
            }
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let client = BilibiliClient(session: session)
        let tracks = try await client.resolveTracks(from: "BV1Bt4y1Y71r")
        let track = try XCTUnwrap(tracks.first)
        let subtitleURL = await client.subtitleURL(for: track)

        XCTAssertNil(subtitleURL)
    }

    private func runBilibiliClientRejectsRandomAISubtitleUntilURLMatchesCID() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var playerRequestCount = 0
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/x/frontend/finger/spi_v2" { throw URLError(.badServerResponse) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path == "/x/web-interface/view" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1Sy4y1m7Uk","aid":798237972,"title":"流沙","pic":"https://i0.hdslb.com/cover.jpg","owner":{"name":"UP主"},"pages":[{"cid":266999608,"page":1,"part":"P1","duration":240,"first_frame":null}]}}"#.utf8)
                return (response, data)
            }
            if url.path == "/x/player/v2" {
                playerRequestCount += 1
                let subtitle = playerRequestCount == 1
                    ? #"{"id_str":"random-track","lan":"ai-zh","subtitle_url":"//aisubtitle.hdslb.com/bfs/ai_subtitle/prod/another-video"}"#
                    : #"{"id_str":"correct-track","lan":"ai-zh","subtitle_url":"//aisubtitle.hdslb.com/bfs/ai_subtitle/prod/798237972266999608-correct"}"#
                let data = Data("{\"code\":0,\"message\":\"0\",\"data\":{\"bvid\":\"BV1Sy4y1m7Uk\",\"cid\":266999608,\"subtitle\":{\"subtitles\":[\(subtitle)]}}}".utf8)
                return (response, data)
            }
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let client = BilibiliClient(session: session)
        let tracks = try await client.resolveTracks(from: "BV1Sy4y1m7Uk")
        let track = try XCTUnwrap(tracks.first)
        let subtitleURL = await client.subtitleURL(for: track)

        XCTAssertEqual(playerRequestCount, 2)
        XCTAssertTrue(subtitleURL?.path.contains("266999608-correct") == true)
    }

    private func runBilibiliClientRequiresRepeatedIdentityForHumanSubtitle() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var playerRequestCount = 0
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/x/frontend/finger/spi_v2" { throw URLError(.badServerResponse) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path == "/x/web-interface/view" {
                let data = Data(#"{"code":0,"message":"0","data":{"bvid":"BV1HumanSub1","aid":1,"title":"人工字幕测试","pic":"https://i0.hdslb.com/cover.jpg","owner":{"name":"UP主"},"pages":[{"cid":42,"page":1,"part":"P1","duration":60,"first_frame":null}]}}"#.utf8)
                return (response, data)
            }
            if url.path == "/x/player/v2" {
                playerRequestCount += 1
                let identity = playerRequestCount == 1 ? "wrong-human" : "correct-human"
                let data = Data("{\"code\":0,\"message\":\"0\",\"data\":{\"bvid\":\"BV1HumanSub1\",\"cid\":42,\"subtitle\":{\"subtitles\":[{\"id_str\":\"\(identity)\",\"lan\":\"zh-CN\",\"subtitle_url\":\"//subtitle.hdslb.com/\(identity).json\"}]}}}".utf8)
                return (response, data)
            }
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let client = BilibiliClient(session: session)
        let tracks = try await client.resolveTracks(from: "BV1HumanSub1")
        let track = try XCTUnwrap(tracks.first)
        let subtitleURL = await client.subtitleURL(for: track)

        XCTAssertEqual(playerRequestCount, 3)
        XCTAssertEqual(subtitleURL?.lastPathComponent, "correct-human.json")
    }

    func testBilibiliQRCodeLoginPersistsReturnedSessionCookie() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = BilibiliSessionFileStore(fileURL: directory.appendingPathComponent("session.json"))
        let cookieStorage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "com.yang.yuangui.tests.\(UUID().uuidString)"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/qrcode/generate") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = Data(#"{"code":0,"message":"0","data":{"url":"https://passport.bilibili.com/qr","qrcode_key":"test-key"}}"#.utf8)
                return (response, data)
            }
            if url.path.hasSuffix("/qrcode/poll") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": "SESSDATA=test-session; Domain=.bilibili.com; Path=/; Secure"]
                )!
                let data = Data(#"{"code":0,"message":"0","data":{"url":"","refresh_token":"refresh-token","timestamp":1,"code":0,"message":"0"}}"#.utf8)
                return (response, data)
            }
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = BilibiliAccountService(session: session, store: fileStore)
        let qrCode = try await service.generateQRCode()
        let state = try await service.pollQRCode(key: qrCode.key)
        let stored = try XCTUnwrap(fileStore.load())

        XCTAssertEqual(qrCode.key, "test-key")
        XCTAssertEqual(state, .succeeded)
        XCTAssertEqual(stored.refreshToken, "refresh-token")
        XCTAssertEqual(stored.cookies.first(where: { $0.name == "SESSDATA" })?.value, "test-session")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: fileStore.fileURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testBilibiliCurrentAccountWithoutStoredSessionSkipsNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = BilibiliSessionFileStore(fileURL: directory.appendingPathComponent("session.json"))
        let cookieStorage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "com.yang.yuangui.tests.\(UUID().uuidString)"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        configuration.httpCookieStorage = cookieStorage
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { _ in
            XCTFail("Logged-out account refresh must not issue a network request")
            throw URLError(.unsupportedURL)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = BilibiliAccountService(session: session, store: fileStore)
        let account = try await service.currentAccount()

        XCTAssertNil(account)
    }

    func testBilibiliFavoritesListsFoldersAndFiltersVideoResources() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch url.path {
            case "/x/v3/fav/folder/created/list":
                let data = Data(#"{"code":0,"message":"0","data":{"list":[{"id":101,"title":"我的音乐","cover":"http://i0.hdslb.com/a.jpg","state":0,"type":0,"media_count":2,"upper":{"name":"测试账号"}}],"has_more":false}}"#.utf8)
                return (response, data)
            case "/x/v3/fav/folder/collected/list":
                let data = Data(#"{"code":0,"message":"0","data":{"list":[{"id":202,"title":"他人歌单","cover":"//i0.hdslb.com/b.jpg","state":0,"type":11,"media_count":3,"upper":{"name":"UP主"}},{"id":203,"title":"视频合集","cover":"","state":0,"type":21,"media_count":4,"upper":{"name":"UP主"}}],"has_more":false}}"#.utf8)
                return (response, data)
            case "/x/v3/fav/resource/ids":
                let data = Data(#"{"code":0,"message":"0","data":[{"id":1,"type":2,"bvid":"BV1xx411c7mD","bv_id":""},{"id":2,"type":12,"bvid":"","bv_id":""},{"id":3,"type":2,"bvid":"","bv_id":"BV19p4y187Kk"}]}"#.utf8)
                return (response, data)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = BilibiliFavoritesService(session: session)
        let folders = try await service.folders(for: 12345)
        let created = try XCTUnwrap(folders.first(where: { $0.kind == .created }))
        let bvids = try await service.videoBVIDs(in: created)

        XCTAssertEqual(folders.map(\.id), [101, 202])
        XCTAssertEqual(created.coverURL?.scheme, "https")
        XCTAssertEqual(folders.last?.ownerName, "UP主")
        XCTAssertEqual(bvids, ["BV1xx411c7mD", "BV19p4y187Kk"])
    }

    func testPlayModesHaveStableUserFacingLabels() {
        XCTAssertEqual(
            MusicPlayMode.allCases.map(\.title),
            ["顺序播放", "单曲循环", "列表循环", "随机播放"].map { AppLocalizer.string($0) }
        )
        XCTAssertEqual(MusicSource.ordered(for: .english), [.appleMusic, .local, .bilibili])
        XCTAssertEqual(MusicSource.ordered(for: .simplifiedChinese), [.appleMusic, .bilibili, .local])
        XCTAssertEqual(
            LyricsFontStyle.allCases.map(\.title),
            ["圆体", "系统字体", "衬线体", "等宽体", "苹方", "宋体", "楷体", "黑体"].map { AppLocalizer.string($0) }
        )
    }

    @MainActor
    func testNewUserDefaultsToAppleMusicAndSavedSourceIsPreserved() async {
        let suiteName = "MusicSourceDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var feature = MusicFeature(defaults: defaults, library: RecordingMusicLibraryCoordinator())
        XCTAssertEqual(feature.playback.source, .appleMusic)
        await feature.shutdown()

        defaults.set(MusicSource.local.rawValue, forKey: "musicSource")
        feature = MusicFeature(defaults: defaults, library: RecordingMusicLibraryCoordinator())
        XCTAssertEqual(feature.playback.source, .local)
        await feature.shutdown()
    }

    func testPlaybackQueueModesAndHistory() throws {
        try runSequentialPlaybackQueueOnlyContainsTracksAfterCurrent()
        runRepeatOneQueueOnlyContainsCurrentTrack()
        runRepeatAllQueueWrapsAndShrinksAsTracksPlay()
        try runRepeatAllQueuePreparesTheNextCycleBeforeCurrentCycleEnds()
        try runShuffleQueueIsStableAndDrivesActualNextTrack()
        try runPlaybackQueuePreviousRestoresConsumedTrack()
        runPlaybackQueueNeverMixesLocalAndBilibiliTracks()
    }

    private func runSequentialPlaybackQueueOnlyContainsTracksAfterCurrent() throws {
        let tracks = makeQueueTracks(count: 4)
        var queue = MusicPlaybackQueue()
        queue.rebuild(playlist: tracks, currentTrackID: tracks[1].id, mode: .sequential)

        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[2].id, tracks[3].id])
        XCTAssertEqual(queue.nextTrackID(playlist: tracks, currentTrackID: tracks[1].id, mode: .sequential), tracks[2].id)
        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[3].id])
    }

    private func runRepeatOneQueueOnlyContainsCurrentTrack() {
        let tracks = makeQueueTracks(count: 3)
        var queue = MusicPlaybackQueue()
        queue.rebuild(playlist: tracks, currentTrackID: tracks[1].id, mode: .repeatOne)

        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[1].id])
        XCTAssertEqual(queue.nextTrackID(playlist: tracks, currentTrackID: tracks[1].id, mode: .repeatOne), tracks[1].id)
        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[1].id])
    }

    private func runRepeatAllQueueWrapsAndShrinksAsTracksPlay() {
        let tracks = makeQueueTracks(count: 4)
        var queue = MusicPlaybackQueue()
        queue.rebuild(playlist: tracks, currentTrackID: tracks[2].id, mode: .repeatAll)

        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[3].id, tracks[0].id, tracks[1].id])
        XCTAssertEqual(queue.nextTrackID(playlist: tracks, currentTrackID: tracks[2].id, mode: .repeatAll), tracks[3].id)
        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[0].id, tracks[1].id])
    }

    private func runRepeatAllQueuePreparesTheNextCycleBeforeCurrentCycleEnds() throws {
        let tracks = makeQueueTracks(count: 3)
        var queue = MusicPlaybackQueue()
        queue.rebuild(playlist: tracks, currentTrackID: tracks[0].id, mode: .repeatAll)

        let second = try XCTUnwrap(queue.nextTrackID(
            playlist: tracks, currentTrackID: tracks[0].id, mode: .repeatAll
        ))
        let third = try XCTUnwrap(queue.nextTrackID(
            playlist: tracks, currentTrackID: second, mode: .repeatAll
        ))

        XCTAssertEqual(second, tracks[1].id)
        XCTAssertEqual(third, tracks[2].id)
        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[0].id, tracks[1].id])
    }

    private func runShuffleQueueIsStableAndDrivesActualNextTrack() throws {
        let tracks = makeQueueTracks(count: 6)
        var queue = MusicPlaybackQueue()
        queue.rebuild(playlist: tracks, currentTrackID: tracks[2].id, mode: .shuffle)
        let scheduled = queue.upcomingTrackIDs

        XCTAssertEqual(scheduled.count, tracks.count - 1)
        XCTAssertEqual(Set(scheduled), Set(tracks.map(\.id)).subtracting([tracks[2].id]))
        XCTAssertEqual(
            queue.nextTrackID(playlist: tracks, currentTrackID: tracks[2].id, mode: .shuffle),
            scheduled.first
        )
        XCTAssertEqual(queue.upcomingTrackIDs, Array(scheduled.dropFirst()))
    }

    private func runPlaybackQueuePreviousRestoresConsumedTrack() throws {
        let tracks = makeQueueTracks(count: 3)
        var queue = MusicPlaybackQueue()
        queue.rebuild(playlist: tracks, currentTrackID: tracks[0].id, mode: .sequential)
        let next = try XCTUnwrap(queue.nextTrackID(
            playlist: tracks, currentTrackID: tracks[0].id, mode: .sequential
        ))

        XCTAssertEqual(next, tracks[1].id)
        XCTAssertEqual(
            queue.previousTrackID(playlist: tracks, currentTrackID: next, mode: .sequential),
            tracks[0].id
        )
        XCTAssertEqual(queue.upcomingTrackIDs, [tracks[1].id, tracks[2].id])
    }

    private func runPlaybackQueueNeverMixesLocalAndBilibiliTracks() {
        let local = makeLocalTrack(id: "local:one", filename: "one.mp3")
        let localTwo = makeLocalTrack(id: "local:two", filename: "two.mp3")
        let bilibili = makeQueueTracks(count: 2)
        let mixed = [local, bilibili[0], localTwo, bilibili[1]]

        var localQueue = MusicPlaybackQueue()
        localQueue.rebuild(playlist: mixed, currentTrackID: local.id, mode: .repeatAll)
        XCTAssertEqual(Set(localQueue.upcomingTrackIDs), Set([localTwo.id]))

        var bilibiliQueue = MusicPlaybackQueue()
        bilibiliQueue.rebuild(playlist: mixed, currentTrackID: bilibili[0].id, mode: .repeatAll)
        XCTAssertEqual(Set(bilibiliQueue.upcomingTrackIDs), Set([bilibili[1].id]))
    }

    @MainActor
    func testLocalImportDuplicateScenarios() async {
        await runDuplicateLocalImportAddsOnlyOneTrack()
        await runDuplicateImportRetainsFailureDetailsAndCleansRejectedArtwork()
    }

    @MainActor
    private func runDuplicateLocalImportAddsOnlyOneTrack() async {
        let defaults = UserDefaults(suiteName: "LocalDuplicate-\(UUID().uuidString)")!
        let track = makeLocalTrack(id: "local:first", filename: "same.mp3")
        let duplicate = makeLocalTrack(id: "local:second", filename: "same.mp3")
        let importer = StubLocalMusicImporter(importResult: LocalMusicImportResult(
            tracks: [track, duplicate],
            failures: []
        ))
        let feature = MusicFeature(
            defaults: defaults,
            localMusicImporter: importer,
            library: RecordingMusicLibraryCoordinator()
        )

        feature.importLocalMusic([URL(fileURLWithPath: "/tmp/selected")])
        for _ in 0..<12 { await Task.yield() }

        XCTAssertEqual(feature.libraryStore.playlist.filter { $0.source == .local }.count, 1)
        XCTAssertEqual(feature.localImportStore.duplicateCount, 1)
        await feature.shutdown()
    }

    @MainActor
    private func runDuplicateImportRetainsFailureDetailsAndCleansRejectedArtwork() async {
        let first = makeLocalTrack(id: "local:first", filename: "same.mp3", artworkKey: "first.artwork")
        let duplicate = makeLocalTrack(id: "local:second", filename: "same.mp3", artworkKey: "duplicate.artwork")
        let artwork = RecordingLocalArtworkRepository()
        let feature = MusicFeature(
            defaults: UserDefaults(suiteName: "LocalFailure-\(UUID().uuidString)")!,
            localMusicImporter: StubLocalMusicImporter(importResult: LocalMusicImportResult(
                tracks: [first, duplicate],
                failures: [LocalMusicImportFailure(filename: "broken.wav", message: "Unreadable")]
            )),
            localArtworkRepository: artwork,
            library: RecordingMusicLibraryCoordinator()
        )

        feature.importLocalMusic([URL(fileURLWithPath: "/tmp/selected")])
        for _ in 0..<12 { await Task.yield() }
        await feature.shutdown()

        XCTAssertEqual(feature.localImportStore.failures.count, 1)
        XCTAssertEqual(feature.localImportStore.failures.first?.filename, "broken.wav")
        let removed = await artwork.removedKeys()
        XCTAssertEqual(removed, ["duplicate.artwork"])
    }

    @MainActor
    func testLocalArtworkLifecycleScenarios() async {
        await runRemovingLocalTracksCleansArtworkAndRestorePrunesOrphans()
        await runRemovingTrackKeepsArtworkStillReferencedByAnotherTrack()
        await runReplacingAndRemovingArtworkUpdatesTheTrackAndCleansOldFiles()
    }

    @MainActor
    private func runRemovingLocalTracksCleansArtworkAndRestorePrunesOrphans() async {
        let first = makeLocalTrack(id: "local:first", filename: "first.mp3", artworkKey: "first.artwork")
        let second = makeLocalTrack(id: "local:second", filename: "second.mp3", artworkKey: "second.artwork")
        let artwork = RecordingLocalArtworkRepository()
        let defaults = UserDefaults(suiteName: "LocalCleanup-\(UUID().uuidString)")!
        defaults.set(MusicSource.local.rawValue, forKey: "musicSource")
        let feature = MusicFeature(
            defaults: defaults,
            localArtworkRepository: artwork,
            library: StaticMusicLibraryCoordinator(snapshot: MusicLibrarySnapshot(playlist: [first, second]))
        )
        for _ in 0..<12 { await Task.yield() }

        feature.remove(first)
        feature.clearPlaylist()
        await feature.shutdown()

        let removed = await artwork.removedKeys()
        let pruneKeys = await artwork.lastPruneKeys()
        XCTAssertEqual(removed, Set(["first.artwork", "second.artwork"]))
        XCTAssertEqual(pruneKeys, Set(["first.artwork", "second.artwork"]))
    }

    @MainActor
    private func runRemovingTrackKeepsArtworkStillReferencedByAnotherTrack() async {
        let first = makeLocalTrack(id: "local:first", filename: "first.mp3", artworkKey: "shared.artwork")
        let second = makeLocalTrack(id: "local:second", filename: "second.mp3", artworkKey: "shared.artwork")
        let artwork = RecordingLocalArtworkRepository()
        let defaults = UserDefaults(suiteName: "SharedArtwork-\(UUID().uuidString)")!
        defaults.set(MusicSource.local.rawValue, forKey: "musicSource")
        let feature = MusicFeature(
            defaults: defaults,
            localArtworkRepository: artwork,
            library: StaticMusicLibraryCoordinator(snapshot: MusicLibrarySnapshot(playlist: [first, second]))
        )
        for _ in 0..<12 { await Task.yield() }

        feature.remove(first)
        for _ in 0..<8 { await Task.yield() }
        let removedAfterFirst = await artwork.removedKeys()
        XCTAssertTrue(removedAfterFirst.isEmpty)

        feature.clearPlaylist()
        await feature.shutdown()
        let removedAfterClear = await artwork.removedKeys()
        XCTAssertEqual(removedAfterClear, ["shared.artwork"])
    }

    @MainActor
    private func runReplacingAndRemovingArtworkUpdatesTheTrackAndCleansOldFiles() async {
        let track = makeLocalTrack(
            id: "local:custom-artwork",
            filename: "song.mp3",
            artworkKey: "embedded.artwork"
        )
        let artwork = RecordingLocalArtworkRepository(importedKey: "custom.artwork")
        let feature = MusicFeature(
            defaults: UserDefaults(suiteName: "CustomArtwork-\(UUID().uuidString)")!,
            localArtworkRepository: artwork,
            library: StaticMusicLibraryCoordinator(snapshot: MusicLibrarySnapshot(playlist: [track]))
        )
        for _ in 0..<12 { await Task.yield() }

        feature.setArtwork(for: track, from: URL(fileURLWithPath: "/tmp/cover.png"))
        for _ in 0..<12 { await Task.yield() }
        XCTAssertEqual(
            feature.libraryStore.playlist.first(where: { $0.id == track.id })?.localArtworkCacheKey,
            "custom.artwork"
        )

        if let updated = feature.libraryStore.playlist.first(where: { $0.id == track.id }) {
            feature.removeArtwork(for: updated)
        }
        await feature.shutdown()

        XCTAssertNil(feature.libraryStore.playlist.first(where: { $0.id == track.id })?.localArtworkCacheKey)
        let removedKeys = await artwork.removedKeys()
        XCTAssertEqual(removedKeys, Set(["embedded.artwork", "custom.artwork"]))
    }

    @MainActor
    func testLocalFileResolutionAndRelocationScenarios() async {
        await runRevealInFinderUsesResolvedLocalURL()
        await runRevealInFinderRequestsRelocationWhenBookmarkIsStale()
        await runMissingLocalFileProducesRelocationStateInsteadOfCrashing()
        await runStaleBookmarkAlsoRequestsRelocation()
    }

    @MainActor
    private func runRevealInFinderUsesResolvedLocalURL() async {
        let track = makeLocalTrack(id: "local:finder", filename: "finder.mp3")
        let revealer = RecordingLocalMusicFileRevealer()
        let feature = MusicFeature(
            defaults: UserDefaults(suiteName: "LocalFinder-\(UUID().uuidString)")!,
            localMusicImporter: StubLocalMusicImporter(),
            localFileRevealer: revealer,
            library: RecordingMusicLibraryCoordinator()
        )

        feature.revealInFinder(track)
        for _ in 0..<12 { await Task.yield() }

        XCTAssertEqual(revealer.revealedURL?.lastPathComponent, "finder.mp3")
        await feature.shutdown()
    }

    @MainActor
    private func runRevealInFinderRequestsRelocationWhenBookmarkIsStale() async {
        let track = makeLocalTrack(id: "local:stale-finder", filename: "missing.mp3")
        let feature = MusicFeature(
            defaults: UserDefaults(suiteName: "StaleFinder-\(UUID().uuidString)")!,
            localMusicImporter: StubLocalMusicImporter(resolveError: .staleBookmark),
            localFileRevealer: RecordingLocalMusicFileRevealer(),
            library: RecordingMusicLibraryCoordinator()
        )

        feature.revealInFinder(track)
        for _ in 0..<12 { await Task.yield() }

        XCTAssertEqual(feature.localImportStore.trackNeedingRelocation?.id, track.id)
        XCTAssertNotNil(feature.localImportStore.errorMessage)
        await feature.shutdown()
    }

    @MainActor
    private func runMissingLocalFileProducesRelocationStateInsteadOfCrashing() async {
        let defaults = UserDefaults(suiteName: "LocalMissing-\(UUID().uuidString)")!
        let track = makeLocalTrack(id: "local:missing", filename: "missing.mp3")
        let importer = StubLocalMusicImporter(resolveError: .missingFile)
        let feature = MusicFeature(
            defaults: defaults,
            urlPlayer: RecordingURLMusicPlayer(),
            lyricsService: StubLyricsProvider(),
            localMusicImporter: importer,
            library: RecordingMusicLibraryCoordinator()
        )

        feature.play(track)
        for _ in 0..<12 { await Task.yield() }

        XCTAssertEqual(feature.localImportStore.trackNeedingRelocation?.id, track.id)
        if case .failed = feature.playback.state {} else { XCTFail("Expected a recoverable failed state") }
        await feature.shutdown()
    }

    @MainActor
    private func runStaleBookmarkAlsoRequestsRelocation() async {
        let track = makeLocalTrack(id: "local:stale", filename: "stale.m4a")
        let feature = MusicFeature(
            defaults: UserDefaults(suiteName: "LocalStale-\(UUID().uuidString)")!,
            urlPlayer: RecordingURLMusicPlayer(),
            lyricsService: StubLyricsProvider(),
            localMusicImporter: StubLocalMusicImporter(resolveError: .staleBookmark),
            library: RecordingMusicLibraryCoordinator()
        )
        feature.play(track)
        for _ in 0..<12 { await Task.yield() }
        XCTAssertEqual(feature.localImportStore.trackNeedingRelocation?.id, track.id)
        await feature.shutdown()
    }

    @MainActor
    func testLocalLRCPrecedesCachedAndRemoteLyrics() async {
        let defaults = UserDefaults(suiteName: "LocalLyrics-\(UUID().uuidString)")!
        defaults.set(MusicSource.local.rawValue, forKey: "musicSource")
        let track = makeLocalTrack(id: "local:lyrics", filename: "lyrics.mp3")
        let cached = LyricsParser.parseLRC("[00:01.00]缓存", source: "cache")
        let local = LyricsParser.parseLRC("[00:01.00]本地", source: "Local LRC")
        let library = StaticMusicLibraryCoordinator(snapshot: MusicLibrarySnapshot(
            playlist: [track],
            currentTrackID: track.id,
            lyricsByTrackID: [track.lyricsCacheKey: cached]
        ))
        let importer = StubLocalMusicImporter(localLyrics: local)
        let feature = MusicFeature(
            defaults: defaults,
            lyricsService: StubLyricsProvider(),
            localMusicImporter: importer,
            library: library
        )
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(feature.lyricsStore.document?.lines.first?.text, "本地")
        await feature.shutdown()
    }

    @MainActor
    func testLocalProgressUpdatesLyricsAndSwitchingSourcePausesURLPlayer() async {
        let defaults = UserDefaults(suiteName: "LocalPlayback-\(UUID().uuidString)")!
        let track = makeLocalTrack(id: "local:playing", filename: "playing.mp3")
        let player = RecordingURLMusicPlayer()
        let importer = StubLocalMusicImporter(
            localLyrics: LyricsParser.parseLRC("[00:01.00]当前歌词", source: "Local LRC")
        )
        let feature = MusicFeature(
            defaults: defaults,
            appleMusic: StubAppleMusicProvider(),
            urlPlayer: player,
            localMusicImporter: importer,
            library: RecordingMusicLibraryCoordinator()
        )

        feature.play(track)
        try? await Task.sleep(for: .milliseconds(50))
        player.onProgress?(1.2, 180)
        XCTAssertEqual(feature.lyricsStore.currentLine?.text, "当前歌词")

        feature.connectAppleMusic()
        XCTAssertGreaterThanOrEqual(player.stopCount, 1)
        await feature.shutdown()
    }

    @MainActor
    func testMusicFeatureComposesDedicatedStoresAndShutdownFlushesDependencies() async {
        let suiteName = "MusicFeatureTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MusicSource.bilibili.rawValue, forKey: "musicSource")
        defaults.set(0.42, forKey: "bilibiliMusicVolume")
        defaults.set(true, forKey: "musicLyricsVisible")
        defaults.set(true, forKey: "musicLyricsPanelLocked")
        let persistence = RecordingMusicLibraryCoordinator()
        let player = RecordingURLMusicPlayer()
        let feature = MusicFeature(
            defaults: defaults,
            urlPlayer: player,
            library: persistence
        )

        XCTAssertEqual(feature.playback.source, .bilibili)
        XCTAssertEqual(feature.playback.volume, 0.42)
        XCTAssertTrue(feature.lyricsPresentation.isVisible)
        XCTAssertTrue(feature.lyricsPresentation.isPanelLocked)
        XCTAssertTrue(feature.libraryStore.playlist.isEmpty)
        XCTAssertNil(feature.lyricsStore.document)
        XCTAssertNil(feature.bilibiliAccountStore.account)
        XCTAssertTrue(feature.bilibiliImportStore.input.isEmpty)

        await feature.shutdown()

        XCTAssertEqual(player.stopCount, 1)
        let saveCount = await persistence.saveCount
        XCTAssertGreaterThanOrEqual(saveCount, 1)
    }

    @MainActor
    func testMusicFeatureDefersURLMusicPlayerUntilPlayback() async {
        let suiteName = "MusicLazyPlayerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var factoryCalls = 0
        let player = RecordingURLMusicPlayer()
        let feature = MusicFeature(
            defaults: defaults,
            bilibili: StubBilibiliMusicProvider(),
            urlPlayerFactory: {
                factoryCalls += 1
                return player
            },
            lyricsService: StubLyricsProvider(),
            library: RecordingMusicLibraryCoordinator()
        )

        XCTAssertEqual(factoryCalls, 0)
        feature.setSource(.bilibili)
        XCTAssertEqual(factoryCalls, 0)

        let track = MusicTrack(
            id: "lazy-bilibili-track",
            source: .bilibili,
            title: "惰性播放器测试",
            artist: "测试歌手",
            album: nil,
            coverURL: nil,
            duration: 180,
            bilibili: BilibiliTrackReference(bvid: "BV1xx411c7mD", aid: 1, cid: 2, page: 1),
            subtitleURL: nil
        )
        feature.play(track)
        feature.play(track)

        XCTAssertEqual(factoryCalls, 1)
        await feature.shutdown()
    }

    @MainActor
    func testURLMusicPlayerReleaseIsDelayedAndCancelledByPlayback() async {
        let suiteName = "MusicPlayerReleaseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var factoryCalls = 0
        let firstPlayer = RecordingURLMusicPlayer()
        let feature = MusicFeature(
            defaults: defaults,
            appleMusic: StubAppleMusicProvider(),
            bilibili: StubBilibiliMusicProvider(),
            urlPlayerFactory: {
                factoryCalls += 1
                return factoryCalls == 1 ? firstPlayer : RecordingURLMusicPlayer()
            },
            lyricsService: StubLyricsProvider(),
            library: RecordingMusicLibraryCoordinator(),
            urlPlayerReleaseDelay: .milliseconds(20)
        )
        let track = MusicTrack(
            id: "release-bilibili-track",
            source: .bilibili,
            title: "延迟释放测试",
            artist: "测试歌手",
            album: nil,
            coverURL: nil,
            duration: 180,
            bilibili: BilibiliTrackReference(bvid: "BV1xx411c7mD", aid: 1, cid: 2, page: 1),
            subtitleURL: nil
        )

        feature.play(track)
        XCTAssertEqual(factoryCalls, 1)
        feature.connectAppleMusic()
        feature.play(track)
        for _ in 0..<25 where firstPlayer.stopCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(firstPlayer.stopCount, 1)

        feature.connectAppleMusic()
        // Switching source stops the player immediately; delayed unloading
        // stops it once more before discarding it. Wait for that second stop
        // instead of assuming the release task has run after a fixed delay.
        for _ in 0..<100 where firstPlayer.stopCount < 3 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(firstPlayer.stopCount, 3)
        feature.play(track)

        XCTAssertEqual(factoryCalls, 2)
        await feature.shutdown()
    }

    @MainActor
    func testAppleMusicSyncRecoversAfterTransientNotRunningResult() async {
        let suiteName = "AppleMusicSyncRecoveryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appleMusic = RecoveringAppleMusicProvider()
        let playback = MusicPlaybackStore(source: .appleMusic, volume: 1)
        playback.activePlaybackSource = .appleMusic
        playback.appleMusicRunning = true
        let coordinator = MusicPlaybackCoordinator(
            playback: playback,
            defaults: defaults,
            appleMusic: appleMusic,
            bilibili: StubBilibiliMusicProvider(),
            localMusicImporter: StubLocalMusicImporter(),
            urlPlayer: nil,
            urlPlayerFactory: { RecordingURLMusicPlayer() },
            urlPlayerReleaseDelay: .seconds(60),
            appleSyncInterval: .milliseconds(10),
            appleUnavailableSyncInterval: .milliseconds(10)
        )

        coordinator.startAppleSyncTask()
        for _ in 0..<50 where playback.currentTrack?.title != "东风破" {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(playback.currentTrack?.title, "东风破")
        XCTAssertTrue(playback.appleMusicRunning)
        let runningCheckCount = await appleMusic.runningCheckCount()
        XCTAssertGreaterThanOrEqual(runningCheckCount, 2)
        await coordinator.shutdown()
    }

    @MainActor
    func testAppleMusicSynchronizationRestartsAfterPresentationResume() async {
        let suiteName = "AppleMusicPresentationResumeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let playback = MusicPlaybackStore(source: .appleMusic, volume: 1)
        playback.activePlaybackSource = .appleMusic
        playback.appleMusicRunning = true
        playback.currentTrack = MusicTrack.appleMusic(
            title: "旧歌曲",
            artist: "测试歌手",
            album: nil,
            duration: 180
        )
        let coordinator = MusicPlaybackCoordinator(
            playback: playback,
            defaults: defaults,
            appleMusic: CurrentTrackAppleMusicProvider(title: "新歌曲"),
            bilibili: StubBilibiliMusicProvider(),
            localMusicImporter: StubLocalMusicImporter(),
            urlPlayer: nil,
            urlPlayerFactory: { RecordingURLMusicPlayer() },
            urlPlayerReleaseDelay: .seconds(60),
            appleSyncInterval: .seconds(60),
            appleUnavailableSyncInterval: .seconds(60)
        )

        coordinator.stopAppleSyncTask()
        coordinator.resumeAppleMusicSynchronization()
        for _ in 0..<50 where playback.currentTrack?.title != "新歌曲" {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(playback.currentTrack?.title, "新歌曲")
        XCTAssertNotNil(coordinator.appleSyncTask)
        await coordinator.shutdown()
    }

    @MainActor
    func testAppleMusicSynchronizationSelfHealsAfterUnexpectedCancellation() async {
        let suiteName = "AppleMusicSyncSelfHealingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appleMusic = AdvancingAppleMusicProvider()
        let playback = MusicPlaybackStore(source: .appleMusic, volume: 1)
        playback.activePlaybackSource = .appleMusic
        playback.appleMusicRunning = true
        let coordinator = MusicPlaybackCoordinator(
            playback: playback,
            defaults: defaults,
            appleMusic: appleMusic,
            bilibili: StubBilibiliMusicProvider(),
            localMusicImporter: StubLocalMusicImporter(),
            urlPlayer: nil,
            urlPlayerFactory: { RecordingURLMusicPlayer() },
            urlPlayerReleaseDelay: .seconds(60),
            appleSyncInterval: .seconds(60),
            appleUnavailableSyncInterval: .seconds(60)
        )

        coordinator.startAppleSyncTask()
        for _ in 0..<50 where await appleMusic.snapshotCount() < 1 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        coordinator.appleSyncTask?.cancel()
        for _ in 0..<50 where playback.currentTrack?.title != "下一首" {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(playback.currentTrack?.title, "下一首")
        XCTAssertNotNil(coordinator.appleSyncTask)
        let snapshotCount = await appleMusic.snapshotCount()
        XCTAssertGreaterThanOrEqual(snapshotCount, 2)
        await coordinator.shutdown()
    }

    @MainActor
    func testMusicSourceSwitchScenarios() async {
        await runSwitchingToBilibiliRestoresItsLastSelectedTrackForStatusDisplay()
        await runSwitchingFromLocalToBilibiliRebuildsStatusQueueForTheNewSource()
    }

    @MainActor
    private func runSwitchingToBilibiliRestoresItsLastSelectedTrackForStatusDisplay() async {
        let suiteName = "MusicSourceSwitchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MusicSource.appleMusic.rawValue, forKey: "musicSource")
        let track = MusicTrack(
            id: "last-bilibili-track", source: .bilibili, title: "上次 B 站歌曲", artist: "测试歌手",
            album: nil, coverURL: nil, duration: 180, bilibili: nil, subtitleURL: nil
        )
        let library = StaticMusicLibraryCoordinator(snapshot: MusicLibrarySnapshot(
            playlist: [track], currentTrackID: track.id, lastPosition: 42
        ))
        let feature = MusicFeature(defaults: defaults, urlPlayer: RecordingURLMusicPlayer(), library: library)
        for _ in 0..<8 { await Task.yield() }

        feature.setSource(.bilibili)

        XCTAssertEqual(feature.playback.source, .bilibili)
        XCTAssertEqual(feature.playback.currentTrack?.id, track.id)
        XCTAssertEqual(feature.playback.currentTrack?.title, "上次 B 站歌曲")
        await feature.shutdown()
    }

    @MainActor
    private func runSwitchingFromLocalToBilibiliRebuildsStatusQueueForTheNewSource() async {
        let suiteName = "MusicSourceQueueSwitchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MusicSource.local.rawValue, forKey: "musicSource")

        let local = makeLocalTrack(id: "local:current", filename: "current.mp3")
        let localNext = makeLocalTrack(id: "local:next", filename: "next.mp3")
        let bilibili = makeQueueTracks(count: 2)
        let library = StaticMusicLibraryCoordinator(snapshot: MusicLibrarySnapshot(
            playlist: [local, bilibili[0], localNext, bilibili[1]],
            playMode: .sequential,
            currentTrackID: local.id
        ))
        let player = RecordingURLMusicPlayer()
        let feature = MusicFeature(
            defaults: defaults,
            urlPlayer: player,
            library: library
        )
        for _ in 0..<8 { await Task.yield() }

        XCTAssertEqual(feature.playback.source, .local)
        XCTAssertEqual(feature.upcomingTracks.map(\.id), [localNext.id])

        feature.setSource(.bilibili)

        XCTAssertEqual(feature.playback.currentTrack?.id, bilibili[0].id)
        XCTAssertEqual(feature.upcomingTracks.map(\.id), [bilibili[1].id])
        XCTAssertTrue(feature.upcomingTracks.allSatisfy { $0.source == .bilibili })
        await feature.shutdown()
    }

    private func makeQueueTracks(count: Int) -> [MusicTrack] {
        (0..<count).map { index in
            MusicTrack(
                id: "queue-\(index)", source: .bilibili, title: "歌曲 \(index)", artist: "歌手",
                album: nil, coverURL: nil, duration: 180, bilibili: nil, subtitleURL: nil
            )
        }
    }

    private func makeLocalTrack(
        id: String,
        filename: String,
        artworkKey: String? = nil
    ) -> MusicTrack {
        MusicTrack(
            id: id,
            source: .local,
            title: filename,
            artist: "Artist",
            album: nil,
            coverURL: nil,
            duration: 180,
            bilibili: nil,
            subtitleURL: nil,
            local: LocalTrackReference(
                bookmarkData: Data([1, 2, 3]),
                originalFilename: filename,
                fileSize: 100
            ),
            localArtworkCacheKey: artworkKey
        )
    }
}

private struct StubLocalMusicMetadataReader: LocalMusicMetadataReading {
    let metadata: LocalMusicMetadata

    func read(at url: URL) async throws -> LocalMusicMetadata { metadata }
}

private actor RecordingLocalArtworkRepository: LocalMusicArtworkManaging {
    private var removed: Set<String> = []
    private var pruneKeys: Set<String> = []
    private let importedKey: String

    init(importedKey: String = "imported.artwork") {
        self.importedKey = importedKey
    }

    func store(_ data: Data, key: String) async throws {}
    func importArtwork(from url: URL) async throws -> String { importedKey }
    func data(for track: MusicTrack) async -> Data? { nil }
    func remove(keys: Set<String>) async { removed.formUnion(keys) }
    func removeOrphans(keeping keys: Set<String>) async { pruneKeys = keys }
    func removedKeys() -> Set<String> { removed }
    func lastPruneKeys() -> Set<String> { pruneKeys }
}

@MainActor
private final class RecordingLocalMusicFileRevealer: LocalMusicFileRevealing {
    private(set) var revealedURL: URL?

    func reveal(_ url: URL) {
        revealedURL = url
    }
}

private actor RecordingMusicLibraryCoordinator: MusicLibraryCoordinating {
    private(set) var saveCount = 0

    func load() async throws -> MusicLibrarySnapshot {
        MusicLibrarySnapshot()
    }

    func scheduleSave(_ snapshot: MusicLibrarySnapshot, revision: UInt64) async {
        saveCount += 1
    }

    func saveNow(_ snapshot: MusicLibrarySnapshot, revision: UInt64) async {
        saveCount += 1
    }
}

private actor StaticMusicLibraryCoordinator: MusicLibraryCoordinating {
    private let snapshot: MusicLibrarySnapshot

    init(snapshot: MusicLibrarySnapshot) {
        self.snapshot = snapshot
    }

    func load() async throws -> MusicLibrarySnapshot { snapshot }
    func scheduleSave(_ snapshot: MusicLibrarySnapshot, revision: UInt64) async {}
    func saveNow(_ snapshot: MusicLibrarySnapshot, revision: UInt64) async {}
}

private actor StubLocalMusicImporter: LocalMusicImporting {
    let importResult: LocalMusicImportResult
    let resolveError: LocalMusicImportError?
    let localDocument: LyricsDocument?

    init(
        importResult: LocalMusicImportResult = LocalMusicImportResult(tracks: [], failures: []),
        resolveError: LocalMusicImportError? = nil,
        localLyrics: LyricsDocument? = nil
    ) {
        self.importResult = importResult
        self.resolveError = resolveError
        self.localDocument = localLyrics
    }

    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult { importResult }

    func resolveURL(for track: MusicTrack) async throws -> URL {
        if let resolveError { throw resolveError }
        return FileManager.default.temporaryDirectory.appending(path: track.local?.originalFilename ?? "track.mp3")
    }

    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack { track }
    func localLyrics(for track: MusicTrack) async throws -> LyricsDocument? { localDocument }
}

private actor StubLyricsProvider: LyricsProviding {
    func lyrics(for track: MusicTrack) async -> LyricsDocument? {
        LyricsParser.parseLRC("[00:01.00]远程", source: "LRCLIB")
    }

    func search(title: String, artist: String, duration: TimeInterval) async throws -> LyricsDocument? {
        nil
    }
}

private struct StubBilibiliMusicProvider: BilibiliMusicProviding {
    func resolveTracks(from input: String) async throws -> [MusicTrack] { [] }

    func audioLocation(for track: MusicTrack) async throws -> BilibiliAudioLocation {
        BilibiliAudioLocation(candidates: [URL(string: "https://example.com/audio.mp3")!])
    }

    func subtitleURL(for track: MusicTrack) async -> URL? { nil }
    func playbackHeaders() async -> [String: String] { [:] }
}

private struct StubAppleMusicProvider: AppleMusicProviding {
    func isRunning() async -> Bool { true }

    func requestSnapshot() async throws -> AppleMusicSnapshot {
        AppleMusicSnapshot(isRunning: true, track: nil, state: .stopped, position: 0, volume: 1)
    }

    func artworkURL(for trackID: String) async -> URL? { nil }
    func play() async {}
    func playPause() async {}
    func pause() async {}
    func previous() async {}
    func next() async {}
    func seek(to position: TimeInterval) async {}
    func setVolume(_ volume: Double) async {}
}

private actor RecoveringAppleMusicProvider: AppleMusicProviding {
    private var runningChecks = 0

    func isRunning() async -> Bool {
        runningChecks += 1
        return runningChecks > 1
    }

    func runningCheckCount() -> Int { runningChecks }

    func requestSnapshot() async throws -> AppleMusicSnapshot {
        AppleMusicSnapshot(
            isRunning: true,
            track: MusicTrack.appleMusic(
                title: "东风破",
                artist: "周杰伦",
                album: "叶惠美",
                duration: 317
            ),
            state: .playing,
            position: 35,
            volume: 0.41
        )
    }

    func artworkURL(for trackID: String) async -> URL? { nil }
    func play() async {}
    func playPause() async {}
    func pause() async {}
    func previous() async {}
    func next() async {}
    func seek(to position: TimeInterval) async {}
    func setVolume(_ volume: Double) async {}
}

private struct CurrentTrackAppleMusicProvider: AppleMusicProviding {
    let title: String

    func isRunning() async -> Bool { true }

    func requestSnapshot() async throws -> AppleMusicSnapshot {
        AppleMusicSnapshot(
            isRunning: true,
            track: MusicTrack.appleMusic(
                title: title,
                artist: "测试歌手",
                album: nil,
                duration: 200
            ),
            state: .playing,
            position: 12,
            volume: 0.5
        )
    }

    func artworkURL(for trackID: String) async -> URL? { nil }
    func play() async {}
    func playPause() async {}
    func pause() async {}
    func previous() async {}
    func next() async {}
    func seek(to position: TimeInterval) async {}
    func setVolume(_ volume: Double) async {}
}

private actor AdvancingAppleMusicProvider: AppleMusicProviding {
    private var snapshots = 0

    func isRunning() async -> Bool { true }

    func snapshotCount() -> Int { snapshots }

    func requestSnapshot() async throws -> AppleMusicSnapshot {
        snapshots += 1
        let isNextTrack = snapshots >= 2
        return AppleMusicSnapshot(
            isRunning: true,
            track: MusicTrack.appleMusic(
                title: isNextTrack ? "下一首" : "上一首",
                artist: "测试歌手",
                album: nil,
                duration: 200
            ),
            state: .playing,
            position: isNextTrack ? 1 : 199,
            volume: 0.5
        )
    }

    func artworkURL(for trackID: String) async -> URL? { nil }
    func play() async {}
    func playPause() async {}
    func pause() async {}
    func previous() async {}
    func next() async {}
    func seek(to position: TimeInterval) async {}
    func setVolume(_ volume: Double) async {}
}

@MainActor
private final class RecordingURLMusicPlayer: URLMusicPlaying {
    var onStateChange: ((MusicPlaybackState) -> Void)?
    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var hasLoadedItem = false
    private(set) var stopCount = 0
    private(set) var pauseCount = 0

    func load(urls: [URL], headers: [String: String], position: TimeInterval, autoplay: Bool) {
        hasLoadedItem = true
    }

    func play() {}
    func playPause() {}
    func pause() { pauseCount += 1 }
    func seek(to position: TimeInterval) {}
    func setVolume(_ volume: Double) {}
    func stop() { stopCount += 1 }
}

private final class LyricsURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
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

    func testCancelledQRCodePollCannotRestoreLoginPresentation() async {
        let accountStore = BilibiliAccountStore()
        let accountService = SuspendedBilibiliAccountService()
        let coordinator = BilibiliMusicCoordinator(
            accountStore: accountStore,
            importStore: BilibiliImportStore(),
            bilibili: SuspendedBilibiliProvider(),
            accountService: accountService,
            loginPollInterval: .zero
        )

        coordinator.startBilibiliLogin()
        await accountService.waitUntilPollingStarted()

        coordinator.cancelBilibiliLogin()
        XCTAssertEqual(accountStore.loginPhase, .loggedOut)
        XCTAssertNil(accountStore.qrCodeURL)

        await accountService.resumePoll(with: .waitingForConfirmation)
        while coordinator.tasks.activeTaskCount > 0 {
            await Task.yield()
        }

        XCTAssertEqual(accountStore.loginPhase, .loggedOut)
        XCTAssertNil(accountStore.qrCodeURL)
        await coordinator.shutdown()
    }

    func testCancelledFavoriteBatchCannotPublishLateProgress() async {
        let provider = SuspendedBatchBilibiliProvider()
        let importStore = BilibiliImportStore()
        let accountStore = BilibiliAccountStore()
        accountStore.account = BilibiliAccount(
            mid: 1,
            name: "Tester",
            avatarURL: nil
        )
        let coordinator = BilibiliMusicCoordinator(
            accountStore: accountStore,
            importStore: importStore,
            bilibili: provider,
            favoritesService: StubBilibiliFavoritesService(
                bvids: ["BV1", "BV2", "BV3", "BV4"]
            )
        )
        let delegate = RecordingBilibiliCoordinatorDelegate()
        coordinator.delegate = delegate
        let folder = BilibiliFavoriteFolder(
            id: 1,
            title: "收藏夹",
            coverURL: nil,
            mediaCount: 4,
            kind: .created,
            ownerName: nil
        )

        coordinator.importBilibiliFavoriteFolder(folder)
        await provider.waitUntilResolveCount(4)

        coordinator.cancelBilibiliFavoriteOperation()
        XCTAssertEqual(importStore.completedCount, 0)
        XCTAssertFalse(importStore.isImportingFavoriteFolder)

        await provider.resumeAll()
        while coordinator.tasks.activeTaskCount > 0 {
            await Task.yield()
        }

        XCTAssertEqual(importStore.completedCount, 0)
        XCTAssertEqual(delegate.importCallCount, 0)
        await coordinator.shutdown()
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
        let artwork = RecordingArtworkRepository()
        let coordinator = LocalMusicCoordinator(
            importStore: LocalMusicImportStore(),
            importer: importer,
            artworkRepository: artwork,
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
        var relocated = track
        relocated.localArtworkCacheKey = "relocated.artwork"
        await importer.resumeRelocation(with: relocated)
        await shutdown.value

        XCTAssertEqual(delegate.replaceTrackCallCount, 0)
        XCTAssertEqual(delegate.persistCallCount, 0)
        let removedArtwork = await artwork.removedKeys()
        XCTAssertEqual(removedArtwork, ["relocated.artwork"])
        XCTAssertEqual(coordinator.tasks.activeTaskCount, 0)
    }

    func testArtworkCreatedDuringShutdownIsRemovedDirectly() async {
        let artwork = SuspendedArtworkRepository()
        let coordinator = LocalMusicCoordinator(
            importStore: LocalMusicImportStore(),
            importer: SuspendedLocalMusicImporter(),
            artworkRepository: artwork,
            fileRevealer: NoopFileRevealer()
        )
        let delegate = RecordingLocalCoordinatorDelegate()
        coordinator.delegate = delegate
        let track = makeLocalTrack(id: "local:artwork")

        coordinator.setArtwork(
            for: track,
            from: URL(fileURLWithPath: "/tmp/cover.png")
        )
        await artwork.waitUntilImportStarted()

        let shutdown = Task { await coordinator.shutdown() }
        while !coordinator.tasks.isShuttingDown {
            await Task.yield()
        }
        await artwork.resumeImport(with: "late.artwork")
        await shutdown.value

        let removedArtwork = await artwork.removedKeys()
        XCTAssertEqual(removedArtwork, ["late.artwork"])
    }

    func testCancelledLocalBatchRemovesUncommittedArtwork() async {
        let importer = SuspendedLocalBatchImporter()
        let artwork = RecordingArtworkRepository()
        let delegate = RecordingLocalCoordinatorDelegate()
        let coordinator = LocalMusicCoordinator(
            importStore: LocalMusicImportStore(),
            importer: importer,
            artworkRepository: artwork,
            fileRevealer: NoopFileRevealer()
        )
        coordinator.delegate = delegate
        var importedTrack = makeLocalTrack(id: "local:late-import")
        importedTrack.localArtworkCacheKey = "late-import.artwork"

        coordinator.importLocalMusic([URL(fileURLWithPath: "/tmp/song.mp3")])
        await importer.waitUntilImportStarted()

        let shutdown = Task { await coordinator.shutdown() }
        while !coordinator.tasks.isShuttingDown {
            await Task.yield()
        }
        await importer.resumeImport(with: LocalMusicImportResult(
            tracks: [importedTrack],
            failures: []
        ))
        await shutdown.value

        let removedArtwork = await artwork.removedKeys()
        XCTAssertEqual(removedArtwork, ["late-import.artwork"])
        XCTAssertEqual(delegate.appendTracksCallCount, 0)
    }

    func testCancellingLyricsSearchClearsSearchingPresentation() async {
        let lyricsStore = LyricsStore()
        let lyricsService = SuspendedLyricsProvider()
        let coordinator = MusicLyricsCoordinator(
            store: lyricsStore,
            presentation: LyricsPresentationStore(
                defaults: UserDefaults(
                    suiteName: "LyricsCancel-\(UUID().uuidString)"
                )!
            ),
            defaults: UserDefaults(
                suiteName: "LyricsCancelDefaults-\(UUID().uuidString)"
            )!,
            lyricsService: lyricsService,
            localMusicImporter: SuspendedLocalMusicImporter(),
            bilibili: SuspendedBilibiliProvider()
        )
        let delegate = RecordingLyricsCoordinatorDelegate(
            track: makeBilibiliTrack(id: "lyrics-cancel")
        )
        coordinator.delegate = delegate

        coordinator.search(title: "Song", artist: "Artist")
        await lyricsService.waitUntilSearchStarted()
        XCTAssertTrue(lyricsStore.isSearching)

        coordinator.resetLibraryLyrics()
        XCTAssertFalse(lyricsStore.isSearching)

        await lyricsService.resumeSearch(with: nil)
        await coordinator.shutdown()
        XCTAssertFalse(lyricsStore.isSearching)
    }

    func testBilibiliSubtitleDoesNotReplaceCachedLRCLIBMatch() async {
        let track = makeBilibiliTrack(id: "preserve-lrclib")
        let bilibili = CountingBilibiliProvider()
        let lyricsStore = LyricsStore()
        let coordinator = MusicLyricsCoordinator(
            store: lyricsStore,
            presentation: LyricsPresentationStore(
                defaults: UserDefaults(suiteName: "LyricsPresentation-\(UUID().uuidString)")!
            ),
            defaults: UserDefaults(suiteName: "LyricsDefaults-\(UUID().uuidString)")!,
            lyricsService: StubLyricsProvider(),
            localMusicImporter: StubLocalMusicImporter(),
            bilibili: bilibili
        )
        let delegate = RecordingLyricsCoordinatorDelegate(track: track)
        coordinator.delegate = delegate
        let matched = LyricsParser.parseLRC("[00:01.00]保留 LRCLIB", source: "LRCLIB")
        coordinator.lyricsByTrackID[track.lyricsCacheKey] = matched

        coordinator.loadLyrics(for: track)
        for _ in 0..<12 { await Task.yield() }
        let subtitleRequests = await bilibili.subtitleRequestCount()

        XCTAssertEqual(lyricsStore.document?.source, "LRCLIB")
        XCTAssertEqual(lyricsStore.document?.lines.first?.text, "保留 LRCLIB")
        XCTAssertEqual(subtitleRequests, 0)
        await coordinator.shutdown()
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

private actor CountingBilibiliProvider: BilibiliMusicProviding {
    private var subtitleRequests = 0

    func resolveTracks(from input: String) async throws -> [MusicTrack] { [] }

    func audioLocation(for track: MusicTrack) async throws -> BilibiliAudioLocation {
        BilibiliAudioLocation(candidates: [URL(string: "https://example.com/audio.mp3")!])
    }

    func subtitleURL(for track: MusicTrack) async -> URL? {
        subtitleRequests += 1
        return URL(string: "https://example.com/subtitle.json")
    }

    func playbackHeaders() async -> [String: String] { [:] }

    func subtitleRequestCount() -> Int { subtitleRequests }
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

private actor SuspendedBatchBilibiliProvider: BilibiliMusicProviding {
    private var continuations:
        [String: CheckedContinuation<[MusicTrack], Error>] = [:]

    func resolveTracks(from input: String) async throws -> [MusicTrack] {
        try await withCheckedThrowingContinuation { continuation in
            continuations[input] = continuation
        }
    }

    func waitUntilResolveCount(_ count: Int) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for (input, continuation) in pending {
            continuation.resume(returning: [
                MusicTrack(
                    id: input,
                    source: .bilibili,
                    title: input,
                    artist: "Artist",
                    album: nil,
                    coverURL: nil,
                    duration: 180,
                    bilibili: nil,
                    subtitleURL: nil
                )
            ])
        }
    }

    func audioLocation(for track: MusicTrack) async throws -> BilibiliAudioLocation {
        BilibiliAudioLocation(candidates: [])
    }

    func subtitleURL(for track: MusicTrack) async -> URL? { nil }
    func playbackHeaders() async -> [String: String] { [:] }
}

private actor SuspendedBilibiliAccountService: BilibiliAccountServicing {
    private var pollContinuation:
        CheckedContinuation<BilibiliLoginPollState, Error>?

    func currentAccount() async throws -> BilibiliAccount? { nil }

    func generateQRCode() async throws -> BilibiliLoginQRCode {
        BilibiliLoginQRCode(url: "https://example.com/qr", key: "qr-key")
    }

    func pollQRCode(key: String) async throws -> BilibiliLoginPollState {
        try await withCheckedThrowingContinuation { continuation in
            pollContinuation = continuation
        }
    }

    func waitUntilPollingStarted() async {
        while pollContinuation == nil {
            await Task.yield()
        }
    }

    func resumePoll(with result: BilibiliLoginPollState) {
        pollContinuation?.resume(returning: result)
        pollContinuation = nil
    }

    func logout() async {}
}

private actor StubBilibiliFavoritesService: BilibiliFavoritesProviding {
    let bvids: [String]

    init(bvids: [String]) {
        self.bvids = bvids
    }

    func folders(for accountMID: Int64) async throws -> [BilibiliFavoriteFolder] {
        []
    }

    func videoBVIDs(in folder: BilibiliFavoriteFolder) async throws -> [String] {
        bvids
    }
}

private actor SuspendedLyricsProvider: LyricsProviding {
    private var searchContinuation:
        CheckedContinuation<LyricsDocument?, Error>?

    func lyrics(for track: MusicTrack) async -> LyricsDocument? { nil }

    func search(
        title: String,
        artist: String,
        duration: TimeInterval
    ) async throws -> LyricsDocument? {
        try await withCheckedThrowingContinuation { continuation in
            searchContinuation = continuation
        }
    }

    func waitUntilSearchStarted() async {
        while searchContinuation == nil {
            await Task.yield()
        }
    }

    func resumeSearch(with document: LyricsDocument?) {
        searchContinuation?.resume(returning: document)
        searchContinuation = nil
    }
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
    private(set) var appendTracksCallCount = 0

    var localDuplicateKeys: Set<String> { [] }
    var referencedArtworkKeys: Set<String> { [] }
    func appendImportedLocalTracks(_ tracks: [MusicTrack]) {
        appendTracksCallCount += 1
    }
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

@MainActor
private final class RecordingLyricsCoordinatorDelegate:
    MusicLyricsCoordinatorDelegate {
    let track: MusicTrack

    init(track: MusicTrack) {
        self.track = track
    }

    var lyricsCurrentTrack: MusicTrack? { track }
    var lyricsPlaybackPosition: TimeInterval { 0 }
    var lyricsPlaybackDuration: TimeInterval { track.duration }

    func seekLyricsPlayback(to position: TimeInterval) {}
    func updateLyricsTrackMetadata(trackID: String, title: String, artist: String) {}
    func updateLyricsSubtitleURL(_ url: URL, trackID: String) {}
    func persistLyricsChanges() {}
    func reportLyricsError(_ message: String?) {}
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

private actor SuspendedLocalBatchImporter: LocalMusicImporting {
    private var importContinuation:
        CheckedContinuation<LocalMusicImportResult, Never>?

    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult {
        await withCheckedContinuation { continuation in
            importContinuation = continuation
        }
    }

    func waitUntilImportStarted() async {
        while importContinuation == nil {
            await Task.yield()
        }
    }

    func resumeImport(with result: LocalMusicImportResult) {
        importContinuation?.resume(returning: result)
        importContinuation = nil
    }

    func resolveURL(for track: MusicTrack) async throws -> URL {
        URL(fileURLWithPath: "/tmp/track.mp3")
    }

    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack {
        track
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

private actor RecordingArtworkRepository: LocalMusicArtworkManaging {
    private var removed: Set<String> = []

    func store(_ data: Data, key: String) async throws {}
    func importArtwork(from url: URL) async throws -> String { "artwork" }
    func data(for track: MusicTrack) async -> Data? { nil }
    func remove(keys: Set<String>) async { removed.formUnion(keys) }
    func removeOrphans(keeping keys: Set<String>) async {}
    func removedKeys() -> Set<String> { removed }
}

private actor SuspendedArtworkRepository: LocalMusicArtworkManaging {
    private var importContinuation: CheckedContinuation<String, Error>?
    private var removed: Set<String> = []

    func store(_ data: Data, key: String) async throws {}

    func importArtwork(from url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            importContinuation = continuation
        }
    }

    func waitUntilImportStarted() async {
        while importContinuation == nil {
            await Task.yield()
        }
    }

    func resumeImport(with key: String) {
        importContinuation?.resume(returning: key)
        importContinuation = nil
    }

    func data(for track: MusicTrack) async -> Data? { nil }
    func remove(keys: Set<String>) async { removed.formUnion(keys) }
    func removeOrphans(keeping keys: Set<String>) async {}
    func removedKeys() -> Set<String> { removed }
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

import AppKit
import SwiftUI
import XCTest
@testable import YuanGUI

@MainActor
final class MusicInstrumentsProfileTests: XCTestCase {
    func testImportProgressDoesNotInvalidateMountedMusicProgressView() async throws {
        guard ProcessInfo.processInfo.environment["YUANGUI_MUSIC_INSTRUMENTS"] == "1" else {
            throw XCTSkip("Set YUANGUI_MUSIC_INSTRUMENTS=1 while recording the SwiftUI template")
        }

        let suiteName = "MusicInstrumentsProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let music = MusicFeature(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 900, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0.01
        window.contentView = NSHostingView(rootView: MusicPlayerView(music: music))
        window.orderFrontRegardless()

        try await Task.sleep(for: .milliseconds(150))
        for completed in 1...100 {
            music.bilibiliImportStore.completedCount = completed
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(150))

        window.close()
        await music.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
    }
}
