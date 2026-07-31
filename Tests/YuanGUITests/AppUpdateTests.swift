import CryptoKit
import Foundation
import XCTest
@testable import YuanGUI

private actor FakeUpdateSourceFetcher: UpdateSourceFetching {
    enum ResultValue: Sendable {
        case update(AvailableUpdate)
        case unsupportedSystemVersion
        case unavailable
        case timedOut
        case invalidManifest
    }

    private let manifestResults: [UpdateAsset.Provider: ResultValue]
    private let apiResult: ResultValue
    private let manifestDelays: [UpdateAsset.Provider: Duration]
    private(set) var manifestCallCount = 0
    private(set) var apiCallCount = 0
    private var manifestCalls: [UpdateAsset.Provider: Int] = [:]

    init(
        gitee: ResultValue = .unavailable,
        github: ResultValue = .unavailable,
        api: ResultValue = .unavailable,
        manifestDelays: [UpdateAsset.Provider: Duration] = [:]
    ) {
        manifestResults = [.gitee: gitee, .github: github]
        apiResult = api
        self.manifestDelays = manifestDelays
    }

    func fetchManifest(endpoint: UpdateEndpoint, timeout: TimeInterval) async throws -> AvailableUpdate {
        manifestCallCount += 1
        manifestCalls[endpoint.provider, default: 0] += 1
        if let delay = manifestDelays[endpoint.provider] {
            try await Task.sleep(for: delay)
        }
        guard case .update(let update) = manifestResults[endpoint.provider] else {
            switch manifestResults[endpoint.provider] {
            case .unsupportedSystemVersion:
                throw AppUpdateError.unsupportedSystemVersion
            case .timedOut:
                throw UpdateSourceAvailabilityError.timedOut
            case .invalidManifest:
                throw AppUpdateError.invalidManifest("fixture")
            default:
                throw UpdateSourceAvailabilityError.resourceUnavailable
            }
        }
        return update
    }

    func manifestCallCount(for provider: UpdateAsset.Provider) -> Int {
        manifestCalls[provider, default: 0]
    }

    func fetchGitHubRelease(timeout: TimeInterval) async throws -> AvailableUpdate {
        apiCallCount += 1
        guard case .update(let update) = apiResult else {
            throw UpdateSourceAvailabilityError.resourceUnavailable
        }
        return update
    }
}

private actor FakeAssetPreparer {
    enum ResultValue: Sendable {
        case success
        case availability(UpdateSourceAvailabilityError)
        case checksumMismatch
        case checksumUnavailable
        case assetSizeMismatch
        case appMissing
        case invalidBundle
        case invalidVersion
        case invalidBuild
        case unsupportedSystemVersion
        case invalidSignature
    }

    private let results: [UpdateAsset.Provider: ResultValue]
    private(set) var attempts: [UpdateAsset.Provider] = []

    init(results: [UpdateAsset.Provider: ResultValue]) {
        self.results = results
    }

    func prepare(asset: UpdateAsset, update: AvailableUpdate) throws -> PreparedAppUpdate {
        attempts.append(asset.provider)
        switch results[asset.provider] ?? .success {
        case .success:
            return PreparedAppUpdate(
                sourceApp: URL(fileURLWithPath: "/tmp/YuanGUI.app"),
                targetApp: URL(fileURLWithPath: "/Applications/YuanGUI.app"),
                mountPoint: URL(fileURLWithPath: "/Volumes/YuanGUI"),
                dmgURL: URL(fileURLWithPath: "/tmp/YuanGUI.dmg")
            )
        case .availability(let error): throw error
        case .checksumMismatch: throw AppUpdateError.checksumMismatch
        case .checksumUnavailable: throw AppUpdateError.checksumUnavailable
        case .assetSizeMismatch: throw AppUpdateError.assetSizeMismatch
        case .appMissing: throw AppUpdateError.appMissing
        case .invalidBundle: throw AppUpdateError.invalidBundle
        case .invalidVersion: throw AppUpdateError.invalidVersion("fixture")
        case .invalidBuild: throw AppUpdateError.invalidBuild("fixture")
        case .unsupportedSystemVersion: throw AppUpdateError.unsupportedSystemVersion
        case .invalidSignature: throw AppUpdateError.invalidSignature
        }
    }
}

private func makeAvailableUpdate(
    _ version: String,
    provider: UpdateAsset.Provider = .github,
    assetCount: Int = 1,
    highlights: [String] = ["A useful update"]
) -> AvailableUpdate {
    let assets = (0..<assetCount).map { index in
        UpdateAsset(
            provider: provider,
            downloadURL: URL(string: "https://updates.example.com/\(provider.rawValue)-\(index).dmg")!,
            sha256: String(repeating: Character("a"), count: 64),
            size: 1024 + Int64(index)
        )
    }
    return AvailableUpdate(
        version: version,
        build: 17,
        minimumSystemVersion: "15.0",
        publishedAt: Date(timeIntervalSince1970: 1_754_000_000),
        localizedHighlights: highlights,
        releasePageURL: URL(string: "https://github.com/YangChen-cn/yuangui/releases/tag/v\(version)"),
        assets: assets,
        metadataSource: .manifest(
            URL(string: "https://updates.example.com/\(provider.rawValue)/latest.json")!,
            provider: provider
        )
    )
}

private func makeUpdateWithGitHubAndGiteeAssets(
    _ version: String = "99.9.9",
    metadataProvider: UpdateAsset.Provider = .github
) -> AvailableUpdate {
    let github = makeAvailableUpdate(version, provider: .github).assets[0]
    let gitee = makeAvailableUpdate(version, provider: .gitee).assets[0]
    return AvailableUpdate(
        version: version,
        build: 17,
        minimumSystemVersion: "15.0",
        publishedAt: Date(timeIntervalSince1970: 1_754_000_000),
        localizedHighlights: ["A useful update"],
        releasePageURL: URL(string: "https://github.com/YangChen-cn/yuangui/releases/tag/v\(version)"),
        assets: [github, gitee],
        metadataSource: .manifest(
            URL(string: metadataProvider == .gitee
                ? "https://gitee.com/yangchen716/yuangui/raw/main/updates/latest.json"
                : "https://raw.githubusercontent.com/YangChen-cn/yuangui/main/updates/latest.json")!,
            provider: metadataProvider
        )
    )
}

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(SemanticVersion.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(SemanticVersion.isNewer("v1.1", than: "1.0.99"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.2", than: "1.0.2"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.1", than: "1.0.2"))
        XCTAssertEqual(SemanticVersion.compare("1.0", "1.0.0"), .orderedSame)
        XCTAssertFalse(SemanticVersion.isStable("2.8.0-beta.1"))
    }

    func testOnlyNetworkAvailabilityFailuresPermitSourceFallback() {
        XCTAssertEqual(
            UpdateSourceAvailabilityError(urlError: URLError(.timedOut)),
            .timedOut
        )
        XCTAssertEqual(
            UpdateSourceAvailabilityError(urlError: URLError(.cannotConnectToHost)),
            .cannotConnectToHost
        )
        XCTAssertNil(UpdateSourceAvailabilityError(urlError: URLError(.badURL)))

        XCTAssertTrue(UpdateSourceAvailabilityError.isFallbackHTTPStatus(408))
        XCTAssertTrue(UpdateSourceAvailabilityError.isFallbackHTTPStatus(429))
        XCTAssertTrue(UpdateSourceAvailabilityError.isFallbackHTTPStatus(503))
        XCTAssertFalse(UpdateSourceAvailabilityError.isFallbackHTTPStatus(404))
        XCTAssertFalse(UpdateSourceAvailabilityError.isFallbackHTTPStatus(401))
    }

    func testManifestDecodesAndValidatesStrictAssetMetadata() throws {
        let json = Data("""
        {
          "schemaVersion": 1,
          "version": "2.7.2",
          "build": 18,
          "minimumSystemVersion": "15.0",
          "publishedAt": "2026-08-01T00:00:00Z",
          "releasePageURL": "https://github.com/YangChen-cn/yuangui/releases/tag/v2.7.2",
          "highlights": { "en": ["A useful update"] },
          "assets": [{
            "provider": "github",
            "url": "https://github.com/YangChen-cn/yuangui/releases/download/v2.7.2/YuanGUI-2.7.2.dmg",
            "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "size": 1024
          }]
        }
        """.utf8)

        let manifest = try UpdateManifestCodec.decodeAndValidate(jsonData: json)
        XCTAssertEqual(manifest.version, "2.7.2")
        XCTAssertEqual(manifest.assets.first?.size, 1024)
    }

    func testManifestRejectsInsecureOrMalformedAsset() throws {
        let base = """
        {
          "schemaVersion": 1,
          "version": "2.7.2",
          "build": 18,
          "minimumSystemVersion": "15.0",
          "publishedAt": "2026-08-01T00:00:00Z",
          "highlights": {},
          "assets": [{
            "provider": "github",
            "url": "%@",
            "sha256": "%@",
            "size": %d
          }]
        }
        """
        let cases = [
            ("http://github.com/update.dmg", String(repeating: "a", count: 64), 1024),
            ("https://github.com/update.dmg", String(repeating: "A", count: 64), 1024),
            ("https://github.com/update.dmg", String(repeating: "a", count: 64), 0),
            ("https://gitee.com/update.dmg", String(repeating: "a", count: 64), 1024)
        ]

        for (url, hash, size) in cases {
            let json = Data(String(format: base, url, hash, size).utf8)
            XCTAssertThrowsError(try UpdateManifestCodec.decodeAndValidate(jsonData: json))
        }
    }

    func testManifestRejectsPrereleaseVersionOnStableChannel() throws {
        let json = Data("""
        {
          "schemaVersion": 1,
          "version": "2.8.0-beta.1",
          "build": 18,
          "minimumSystemVersion": "15.0",
          "publishedAt": "2026-08-01T00:00:00Z",
          "highlights": {},
          "assets": [{
            "provider": "github",
            "url": "https://github.com/YangChen-cn/yuangui/releases/download/v2.8.0-beta.1/YuanGUI.dmg",
            "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "size": 1024
          }]
        }
        """.utf8)

        XCTAssertThrowsError(try UpdateManifestCodec.decodeAndValidate(jsonData: json))
    }

    func testSHA256StreamsLargeFixtureAndReturnsLowercaseHex() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuangui-sha256-(UUID().uuidString).fixture")
        let data = Data(repeating: 0x5A, count: 2 * 1024 * 1024 + 17)
        try data.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try sha256(of: fileURL), expected)
        XCTAssertEqual(try sha256(of: fileURL), try sha256(of: fileURL).lowercased())
    }

    func testDualSourceKeepsValidGiteeManifestWhenGitHubIsUnavailable() async throws {
        let gitee = makeAvailableUpdate("99.9.9", provider: .gitee)
        let fetcher = FakeUpdateSourceFetcher(gitee: .update(gitee), github: .timedOut)
        let service = AppUpdateService(sourceFetcher: fetcher)

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("A newer Gitee manifest should be available")
        }
        XCTAssertEqual(update.version, "99.9.9")
        XCTAssertEqual(update.metadataSource, gitee.metadataSource)
        let apiCalls = await fetcher.apiCallCount
        XCTAssertEqual(apiCalls, 0)
        let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
        XCTAssertEqual(giteeCalls, 1)
    }

    func testUnsupportedGitHubManifestDoesNotRequestGiteeOrReleaseAPI() async {
        let fetcher = FakeUpdateSourceFetcher(
            github: .unsupportedSystemVersion,
            api: .update(makeAvailableUpdate("99.9.9"))
        )
        let service = AppUpdateService(sourceFetcher: fetcher)

        do {
            _ = try await service.checkForUpdate()
            XCTFail("An unsupported primary manifest must stop the check")
        } catch AppUpdateError.unsupportedSystemVersion {
            let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
            let apiCalls = await fetcher.apiCallCount
            XCTAssertEqual(giteeCalls, 0)
            XCTAssertEqual(apiCalls, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGitHubManifestWinsAndDoesNotRequestGiteeWhenGiteeIsNewer() async throws {
        let github = makeAvailableUpdate("99.9.8", provider: .github)
        let gitee = makeAvailableUpdate("99.9.9", provider: .gitee)
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .update(gitee),
            github: .update(github)
        )
        let service = AppUpdateService(sourceFetcher: fetcher)

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("GitHub manifest should be selected")
        }
        XCTAssertEqual(update.version, "99.9.8")
        XCTAssertEqual(update.metadataSource, github.metadataSource)
        let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
        XCTAssertEqual(giteeCalls, 0)
    }

    func testHedgedGiteeCannotOverrideGitHubBeforePrimaryDeadline() async throws {
        let github = makeAvailableUpdate("99.9.8", provider: .github)
        let gitee = makeAvailableUpdate("99.9.9", provider: .gitee)
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .update(gitee),
            github: .update(github),
            manifestDelays: [
                .github: .milliseconds(200),
                .gitee: .milliseconds(20)
            ]
        )
        let service = AppUpdateService(
            sourceFetcher: fetcher,
            manifestHedge: UpdateManifestHedgeConfiguration(
                giteeStartDelay: .milliseconds(50),
                githubPrimaryDeadline: .milliseconds(500)
            )
        )

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("GitHub should remain authoritative before its deadline")
        }
        XCTAssertEqual(update.version, "99.9.8")
        let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
        XCTAssertEqual(giteeCalls, 1)
    }

    func testHedgedGiteeIsUsedWhenGitHubMissesPrimaryDeadline() async throws {
        let github = makeAvailableUpdate("99.9.8", provider: .github)
        let gitee = makeAvailableUpdate("99.9.9", provider: .gitee)
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .update(gitee),
            github: .update(github),
            manifestDelays: [
                .github: .milliseconds(1_500),
                .gitee: .milliseconds(350)
            ]
        )
        let service = AppUpdateService(
            sourceFetcher: fetcher,
            manifestHedge: UpdateManifestHedgeConfiguration(
                giteeStartDelay: .milliseconds(100),
                githubPrimaryDeadline: .milliseconds(250),
                automaticBackupDeadline: .seconds(2)
            )
        )

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("Gitee should be used after the GitHub primary deadline")
        }
        XCTAssertEqual(update.version, "99.9.9")
        let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
        XCTAssertEqual(giteeCalls, 1)
    }

    func testInvalidGitHubManifestDoesNotRequestGitee() async {
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .update(makeAvailableUpdate("99.9.9", provider: .gitee)),
            github: .invalidManifest
        )
        let service = AppUpdateService(sourceFetcher: fetcher)

        do {
            _ = try await service.checkForUpdate()
            XCTFail("An invalid primary manifest must not fall back")
        } catch AppUpdateError.invalidManifest {
            let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
            XCTAssertEqual(giteeCalls, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGitHubAPIIsUsedOnlyWhenBothManifestsFail() async throws {
        let apiBase = makeAvailableUpdate("99.9.9", provider: .github)
        let apiUpdate = AvailableUpdate(
            version: apiBase.version,
            build: apiBase.build,
            minimumSystemVersion: apiBase.minimumSystemVersion,
            publishedAt: apiBase.publishedAt,
            localizedHighlights: apiBase.localizedHighlights,
            releasePageURL: apiBase.releasePageURL,
            assets: apiBase.assets,
            metadataSource: .githubReleaseAPI
        )
        let fetcher = FakeUpdateSourceFetcher(api: .update(apiUpdate))
        let service = AppUpdateService(sourceFetcher: fetcher)

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("GitHub API fallback should provide the update")
        }
        XCTAssertEqual(update.metadataSource, .githubReleaseAPI)
        let apiCalls = await fetcher.apiCallCount
        XCTAssertEqual(apiCalls, 1)
    }

    func testManualManifestResultDoesNotRequireGitHubReleaseNotes() async throws {
        let manifestUpdate = makeAvailableUpdate(
            "99.9.9",
            provider: .gitee,
            highlights: ["国内镜像中的更新摘要"]
        )
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .update(manifestUpdate),
            api: .update(makeAvailableUpdate("99.9.9", provider: .github))
        )
        let service = AppUpdateService(sourceFetcher: fetcher)

        let result = try await service.checkForUpdate(mode: .manual)
        guard case .available(_, let notes) = result else {
            return XCTFail("A valid Gitee manifest should be available")
        }
        XCTAssertEqual(notes, "- 国内镜像中的更新摘要")
        let apiCalls = await fetcher.apiCallCount
        XCTAssertEqual(apiCalls, 0)
    }

    func testGitHubDMGSuccessDoesNotTryGitee() async throws {
        let preparer = FakeAssetPreparer(results: [.github: .success, .gitee: .availability(.timedOut)])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
        let attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.github])
    }

    func testGiteeManifestDownloadsGiteeBeforeGitHub() async throws {
        let preparer = FakeAssetPreparer(results: [
            .gitee: .success,
            .github: .availability(.timedOut)
        ])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        _ = try await service.prepare(
            makeUpdateWithGitHubAndGiteeAssets(metadataProvider: .gitee)
        )
        let attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.gitee])
    }

    func testGitHubDMGNetworkFailureFallsBackToGitee() async throws {
        let preparer = FakeAssetPreparer(results: [
            .github: .availability(.cannotConnectToHost),
            .gitee: .success
        ])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        let prepared = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
        XCTAssertEqual(prepared.dmgURL.path, "/tmp/YuanGUI.dmg")
        let attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.github, .gitee])
    }

    func testGitHubDMGIntegrityFailureDoesNotTryGitee() async {
        let failures: [FakeAssetPreparer.ResultValue] = [
            .checksumMismatch,
            .checksumUnavailable,
            .assetSizeMismatch,
            .appMissing,
            .invalidBundle,
            .invalidVersion,
            .invalidBuild,
            .unsupportedSystemVersion,
            .invalidSignature
        ]

        for failure in failures {
            let preparer = FakeAssetPreparer(results: [.github: failure, .gitee: .success])
            let service = AppUpdateService(assetPreparer: { asset, update in
                try await preparer.prepare(asset: asset, update: update)
            })

            do {
                _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
                XCTFail("Integrity/configuration failure should stop without fallback: \(failure)")
            } catch {
                let attempts = await preparer.attempts
                XCTAssertEqual(attempts, [.github])
            }
        }
    }

    func testGitHubAndGiteeDownloadNetworkFailuresReturnStableError() async {
        let preparer = FakeAssetPreparer(results: [
            .github: .availability(.timedOut),
            .gitee: .availability(.httpStatus(503))
        ])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        do {
            _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
            XCTFail("Both network failures should be reported")
        } catch AppUpdateError.updateSourcesUnavailable {
            let attempts = await preparer.attempts
            XCTAssertEqual(attempts, [.github, .gitee])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamDownloadWritesBodyAndMapsFallbackHTTPStatuses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let service = AppUpdateService(session: URLSession(configuration: configuration))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-StreamDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        let body = Data("streamed fixture body".utf8)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body
        let response = try await service.streamDownload(URLRequest(url: url), to: destination)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: destination), body)

        for statusCode in [408, 429, 503] {
            UpdateStreamURLProtocol.statusCode = statusCode
            do {
                _ = try await service.streamDownload(
                    URLRequest(url: url),
                    to: directory.appendingPathComponent("status-\(statusCode).dmg")
                )
                XCTFail("HTTP \(statusCode) should permit source fallback")
            } catch let error as UpdateSourceAvailabilityError {
                XCTAssertEqual(error, .httpStatus(statusCode))
            } catch {
                XCTFail("Unexpected error for HTTP \(statusCode): \(error)")
            }
        }
    }

    func testUnsupportedManifestDoesNotFallBackToGitHubAPI() async {
        let apiUpdate = makeAvailableUpdate("99.9.9", provider: .github)
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .unsupportedSystemVersion,
            github: .unsupportedSystemVersion,
            api: .update(apiUpdate)
        )
        let service = AppUpdateService(sourceFetcher: fetcher)

        do {
            _ = try await service.checkForUpdate()
            XCTFail("Unsupported manifests must not be bypassed by the API fallback")
        } catch AppUpdateError.unsupportedSystemVersion {
            let apiCalls = await fetcher.apiCallCount
            XCTAssertEqual(apiCalls, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAllUpdateSourcesFailWithoutSurfacingAFalseUpdate() async {
        let fetcher = FakeUpdateSourceFetcher()
        let service = AppUpdateService(sourceFetcher: fetcher)

        do {
            _ = try await service.checkForUpdate()
            XCTFail("All update sources should fail")
        } catch AppUpdateError.updateManifestUnavailable {
            let apiCalls = await fetcher.apiCallCount
            let githubCalls = await fetcher.manifestCallCount(for: .github)
            let giteeCalls = await fetcher.manifestCallCount(for: .gitee)
            XCTAssertEqual(apiCalls, 1)
            XCTAssertEqual(githubCalls, 1)
            XCTAssertEqual(giteeCalls, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGitHubReleaseDecodesNotesAndFindsDMG() throws {
        let data = Data(#"{"tag_name":"v1.0.2","name":"元圭与 VCC 1.0.2","body":"更新日志","html_url":"https://github.com/YangChen-cn/yuangui/releases/tag/v1.0.2","assets":[{"name":"YuanGUI-1.0.2.dmg","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v1.0.2/YuanGUI-1.0.2.dmg","size":1234}]}"#.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        XCTAssertEqual(release.version, "1.0.2")
        XCTAssertEqual(release.body, "更新日志")
        XCTAssertEqual(release.dmgAsset?.name, "YuanGUI-1.0.2.dmg")
    }

    func testGitHubReleaseSelectsLocalizedReleaseNotesAsset() throws {
        let data = Data(#"{"tag_name":"v2.7.0","name":"YuanGUI 2.7.0","body":"English fallback","html_url":"https://github.com/YangChen-cn/yuangui/releases/tag/v2.7.0","assets":[{"name":"RELEASE_NOTES.md","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v2.7.0/RELEASE_NOTES.md","size":10},{"name":"RELEASE_NOTES.zh-CN.md","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v2.7.0/RELEASE_NOTES.zh-CN.md","size":12}]}"#.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        XCTAssertEqual(release.releaseNotesAsset(for: .english)?.name, "RELEASE_NOTES.md")
        XCTAssertEqual(release.releaseNotesAsset(for: .simplifiedChinese)?.name, "RELEASE_NOTES.zh-CN.md")
        XCTAssertNotNil(release.releaseNotesAsset(for: .system))
    }

    func testManualCheckReturnsCompleteLocalizedReleaseNotes() async throws {
        let releaseURL = AppUpdateService.latestReleaseURL
        let notesURL = URL(string: "https://github.com/YangChen-cn/yuangui/releases/download/v99.9.9/RELEASE_NOTES.zh-CN.md")!
        let releaseData = Data("""
        {
          "tag_name": "v99.9.9",
          "name": "YuanGUI 99.9.9",
          "body": "English fallback",
          "html_url": "https://github.com/YangChen-cn/yuangui/releases/tag/v99.9.9",
          "assets": [
            {
              "name": "RELEASE_NOTES.zh-CN.md",
              "browser_download_url": "\(notesURL.absoluteString)",
              "size": 128
            },
            {
              "name": "YuanGUI-99.9.9.dmg",
              "browser_download_url": "https://github.com/YangChen-cn/yuangui/releases/download/v99.9.9/YuanGUI-99.9.9.dmg",
              "size": 1024
            }
          ]
        }
        """.utf8)
        let fullNotes = """
        ## 更新说明
        - 第一条完整中文说明
        - 第二条完整中文说明
        - 第三条完整中文说明
        """.data(using: .utf8)!

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateReleaseURLProtocol.self]
        UpdateReleaseURLProtocol.handler = { request in
            if request.url == releaseURL {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, releaseData)
            }
            if request.url == notesURL {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, fullNotes)
            }
            throw URLError(.resourceUnavailable)
        }
        defer { UpdateReleaseURLProtocol.handler = nil }

        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            languageProvider: { .simplifiedChinese }
        )
        let result = try await service.checkForUpdate(mode: .manual)
        guard case .available(_, let notes) = result else {
            return XCTFail("Manual check should find the fixture update")
        }
        XCTAssertEqual(notes, String(data: fullNotes, encoding: .utf8))
        XCTAssertTrue(try XCTUnwrap(notes).contains("第三条完整中文说明"))
    }

    func testReleaseNotesKeepGitHubMarkdownStructure() {
        let rows = ReleaseNoteRow.parse("""
        ## 改进
        - 修复播放器布局
        1. 更新歌词交互

        补充说明会单独换行。
        """)

        XCTAssertEqual(rows.map(\.kind), [.heading, .bullet, .bullet, .paragraph])
        XCTAssertEqual(rows.map(\.text), ["改进", "修复播放器布局", "更新歌词交互", "补充说明会单独换行。"])
        XCTAssertEqual(
            ReleaseNoteRow.parse("").map(\.text),
            [AppLocalizer.string("此 Release 没有填写更新日志。")]
        )
    }

    func testInstallerBoundsWaitForOldProcessBeforeReplacingApp() {
        let script = AppUpdateInstallerScript.source
        XCTAssertTrue(script.contains("wait_attempts >= 50"))
        XCTAssertTrue(script.contains("kill -TERM"))
        XCTAssertTrue(script.contains("force_attempts >= 25"))
        XCTAssertTrue(script.contains("kill -KILL"))
        XCTAssertTrue(script.contains("/usr/bin/open -n \"$target_app\""))
    }

    func testInstallerScriptHasValidZshSyntax() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuangui-installer-test-\(UUID().uuidString).zsh")
        try Data(AppUpdateInstallerScript.source.utf8).write(to: scriptURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n", scriptURL.path]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let error = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
    }
}

private final class UpdateReleaseURLProtocol: URLProtocol {
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

private final class UpdateStreamURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: Self.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if (200..<300).contains(Self.statusCode) {
            client?.urlProtocol(self, didLoad: Self.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
