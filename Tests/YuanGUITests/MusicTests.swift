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
                let subtitleURL = try XCTUnwrap(track.subtitleURL)
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

        let service = LyricsService(session: session)
        let document = try await service.search(title: "测试歌曲", artist: "", duration: 120)

        XCTAssertEqual(document?.lines.first?.text, "第一句")
        XCTAssertEqual(capturedRequest?.timeoutInterval, 30)
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

    func testLyricsServiceAcceptsSwappedTrackAndArtistFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        LyricsURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = Data(#"[{"trackName":"陶喆","artistName":"讨厌红楼梦","duration":235,"syncedLyrics":"[00:01.00]交换字段也能匹配"}]"#.utf8)
            return (response, data)
        }
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let service = LyricsService(session: session)
        let document = try await service.search(title: "讨厌红楼梦", artist: "陶喆", duration: 235)

        XCTAssertEqual(document?.lines.first?.text, "交换字段也能匹配")
    }

    func testLyricsServiceDoesNotRunSlowBroadFallbackAfterExactMiss() async throws {
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
        XCTAssertEqual(requestCount, 1)
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

    func testBilibiliClientFallsBackToPlayerSubtitleURL() async throws {
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

        let tracks = try await BilibiliClient(session: session).resolveTracks(from: "BV1Bt4y1Y71r")

        XCTAssertEqual(tracks.first?.subtitleURL?.absoluteString, "https://aisubtitle.hdslb.com/test.json")
    }

    func testBilibiliClientUsesEachPagesExactCIDInsteadOfViewSubtitle() async throws {
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

        let tracks = try await BilibiliClient(session: session).resolveTracks(from: "BV1Bt4y1Y71r")

        XCTAssertEqual(requestedCIDs, ["101", "202"])
        XCTAssertEqual(
            tracks.map(\.subtitleURL?.lastPathComponent),
            ["628037055-cid-101.json", "628037055-cid-202.json"]
        )
    }

    func testBilibiliClientRejectsSubtitleResponseForAnotherCID() async throws {
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

        let tracks = try await BilibiliClient(session: session).resolveTracks(from: "BV1Bt4y1Y71r")

        XCTAssertNil(tracks.first?.subtitleURL)
    }

    func testBilibiliClientRejectsRandomAISubtitleUntilURLMatchesCID() async throws {
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

        let tracks = try await BilibiliClient(session: session).resolveTracks(from: "BV1Sy4y1m7Uk")

        XCTAssertEqual(playerRequestCount, 2)
        XCTAssertTrue(tracks.first?.subtitleURL?.path.contains("266999608-correct") == true)
    }

    func testBilibiliClientRequiresRepeatedIdentityForHumanSubtitle() async throws {
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

        let tracks = try await BilibiliClient(session: session).resolveTracks(from: "BV1HumanSub1")

        XCTAssertEqual(playerRequestCount, 3)
        XCTAssertEqual(tracks.first?.subtitleURL?.lastPathComponent, "correct-human.json")
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
