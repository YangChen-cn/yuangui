import Foundation
import XCTest
@testable import YuanGUI

final class MusicTests: XCTestCase {
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
        let player = BilibiliPlayerEngine()
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

    func testLyricsServiceMatchesByTitleWhenArtistIsEmptyAndSetsTimeout() async throws {
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

        let service = LyricsService(session: session, requestTimeout: 0.25)
        let document = try await service.search(title: "测试歌曲", artist: "", duration: 120)

        XCTAssertEqual(document?.lines.first?.text, "第一句")
        XCTAssertEqual(capturedRequest?.timeoutInterval, 0.25)
        let items = URLComponents(url: try XCTUnwrap(capturedRequest?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "track_name" })?.value, "测试歌曲")
        XCTAssertNil(items?.first(where: { $0.name == "artist_name" }))
    }

    func testLyricsServiceReportsTimeout() async throws {
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

    func testPlayModesHaveStableUserFacingLabels() {
        XCTAssertEqual(MusicPlayMode.allCases.map(\.title), ["顺序播放", "单曲循环", "列表循环"])
        XCTAssertEqual(MusicSource.allCases.map(\.title), ["Apple Music", "哔哩哔哩"])
        XCTAssertEqual(LyricsFontStyle.allCases.map(\.title), ["圆体", "系统字体", "衬线体", "等宽体"])
    }
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
