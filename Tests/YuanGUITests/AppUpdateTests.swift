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
        /// Simulates the sustained-slow monitor firing during the transfer.
        case downloadTooSlow
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
        case .downloadTooSlow: throw UpdateSourceAvailabilityError.downloadTooSlow
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

    func testBuildAwareVersionComparison() async throws {
        // A same version is only an update when the remote build is higher;
        // the GitHub API fallback carries no build and never counts on
        // equality. The local version comes from the running bundle, so the
        // cases are derived from it instead of a hardcoded release.
        let currentVersion = AppVersionInfo.version
        let currentBuild = Int(AppVersionInfo.build) ?? 0
        let cases: [(version: String, build: Int?, expectsUpdate: Bool)] = [
            (currentVersion, currentBuild + 1, true),
            (currentVersion, currentBuild, false),
            (currentVersion, currentBuild - 1, false),
            (currentVersion, nil, false),
            ("0.0.1", 9_999, false)
        ]
        for (version, build, expectsUpdate) in cases {
            let update = AvailableUpdate(
                version: version,
                build: build,
                minimumSystemVersion: "15.0",
                publishedAt: Date(timeIntervalSince1970: 1_754_000_000),
                localizedHighlights: ["fixture"],
                releasePageURL: nil,
                assets: [UpdateAsset(
                    provider: .github,
                    downloadURL: URL(string: "https://github.com/YangChen-cn/yuangui/releases/download/v2.8.0/YuanGUI-2.8.0.dmg")!,
                    sha256: String(repeating: "a", count: 64),
                    size: 1024
                )],
                metadataSource: .manifest(
                    URL(string: "https://raw.githubusercontent.com/YangChen-cn/yuangui/main/updates/latest.json")!,
                    provider: .github
                )
            )
            let fetcher = FakeUpdateSourceFetcher(github: .update(update))
            let service = AppUpdateService(sourceFetcher: fetcher)
            let result = try await service.checkForUpdate()
            switch result {
            case .available:
                XCTAssertTrue(expectsUpdate, "\(version)/\(String(describing: build)) should be an update")
            case .upToDate:
                XCTAssertFalse(expectsUpdate, "\(version)/\(String(describing: build)) should be up to date")
            }
        }
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

    func testManifestValidationScenarios() throws {
        try runManifestDecodesAndValidatesStrictAssetMetadata()
        try runManifestRejectsInsecureOrMalformedAsset()
        try runManifestRejectsPrereleaseVersionOnStableChannel()
        try runSHA256StreamsLargeFixtureAndReturnsLowercaseHex()
    }

    private func runManifestDecodesAndValidatesStrictAssetMetadata() throws {
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

    private func runManifestRejectsInsecureOrMalformedAsset() throws {
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

    private func runManifestRejectsPrereleaseVersionOnStableChannel() throws {
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

    private func runSHA256StreamsLargeFixtureAndReturnsLowercaseHex() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuangui-sha256-(UUID().uuidString).fixture")
        let data = Data(repeating: 0x5A, count: 2 * 1024 * 1024 + 17)
        try data.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try sha256(of: fileURL), expected)
        XCTAssertEqual(try sha256(of: fileURL), try sha256(of: fileURL).lowercased())
    }

    func testManifestSourceSelectionScenarios() async throws {
        try await runDualSourceKeepsValidGiteeManifestWhenGitHubIsUnavailable()
        await runUnsupportedGitHubManifestDoesNotRequestGiteeOrReleaseAPI()
        try await runGitHubManifestWinsAndDoesNotRequestGiteeWhenGiteeIsNewer()
        try await runHedgedGiteeCannotOverrideGitHubBeforePrimaryDeadline()
        try await runHedgedGiteeIsUsedWhenGitHubMissesPrimaryDeadline()
        try await runLateValidGitHubManifestSurvivesGiteeValidationFailure()
        await runInvalidGitHubManifestDoesNotRequestGitee()
        try await runGitHubAPIIsUsedOnlyWhenBothManifestsFail()
        try await runManualManifestResultDoesNotRequireGitHubReleaseNotes()
    }

    private func runDualSourceKeepsValidGiteeManifestWhenGitHubIsUnavailable() async throws {
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

    private func runUnsupportedGitHubManifestDoesNotRequestGiteeOrReleaseAPI() async {
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

    private func runGitHubManifestWinsAndDoesNotRequestGiteeWhenGiteeIsNewer() async throws {
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

    private func runHedgedGiteeCannotOverrideGitHubBeforePrimaryDeadline() async throws {
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

    private func runHedgedGiteeIsUsedWhenGitHubMissesPrimaryDeadline() async throws {
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

    private func runLateValidGitHubManifestSurvivesGiteeValidationFailure() async throws {
        let github = makeAvailableUpdate("99.9.8", provider: .github)
        let fetcher = FakeUpdateSourceFetcher(
            gitee: .invalidManifest,
            github: .update(github),
            manifestDelays: [
                .github: .milliseconds(500)
            ]
        )
        let service = AppUpdateService(
            sourceFetcher: fetcher,
            manifestHedge: UpdateManifestHedgeConfiguration(
                giteeStartDelay: .milliseconds(100),
                githubPrimaryDeadline: .milliseconds(250),
                automaticBackupDeadline: .seconds(1)
            )
        )

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("A valid late GitHub manifest should survive a Gitee validation failure")
        }
        XCTAssertEqual(update.version, "99.9.8")
    }

    private func runInvalidGitHubManifestDoesNotRequestGitee() async {
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

    private func runGitHubAPIIsUsedOnlyWhenBothManifestsFail() async throws {
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

    private func runManualManifestResultDoesNotRequireGitHubReleaseNotes() async throws {
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

    func testDownloadSourceSelectionScenarios() async throws {
        try await runGitHubDMGSuccessDoesNotTryGitee()
        try await runGiteeManifestDownloadsGiteeBeforeGitHub()
        try await runGitHubDMGNetworkFailureFallsBackToGitee()
        await runGitHubDMGIntegrityFailureDoesNotTryGitee()
        await runGitHubAndGiteeDownloadNetworkFailuresReturnStableError()
    }

    private func runGitHubDMGSuccessDoesNotTryGitee() async throws {
        let preparer = FakeAssetPreparer(results: [.github: .success, .gitee: .availability(.timedOut)])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
        let attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.github])
    }

    private func runGiteeManifestDownloadsGiteeBeforeGitHub() async throws {
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

    private func runGitHubDMGNetworkFailureFallsBackToGitee() async throws {
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

    private func runGitHubDMGIntegrityFailureDoesNotTryGitee() async {
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

    private func runGitHubAndGiteeDownloadNetworkFailuresReturnStableError() async {
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

    func testDownloadSlowSourceSelectionScenarios() async throws {
        try await runGitHubSlowDownloadFallsBackToGiteeAndCaches()
        try await runGitHubSlowWithoutGiteeAssetReportsUnavailable()
        try await runGitHubSlowAndGiteeFailsDoesNotCache()
        try await runGitHubSlowAndGiteeIntegrityFailureStops()
    }

    func testUpdateSourcePreferenceScenarios() async throws {
        try await runManifestPreferencePinsSource()
        try await runPreparePreferencePinsSource()
        try await runPreparePreferenceWithoutAssetReportsUnavailable()
        await runStorePreferencePersists()
        await runStorePreferenceChangeDiscardsStaleResultAndRechecks()
    }

    private func runManifestPreferencePinsSource() async throws {
        let cases: [(UpdateSourcePreference, UpdateAsset.Provider)] = [
            (.github, .github),
            (.gitee, .gitee)
        ]
        for (preference, expectedProvider) in cases {
            let fetcher = FakeUpdateSourceFetcher(
                gitee: .update(makeAvailableUpdate("99.9.9", provider: .gitee)),
                github: .update(makeAvailableUpdate("99.9.9", provider: .github)),
                api: .update(makeAvailableUpdate("99.9.9", provider: .github))
            )
            let service = AppUpdateService(
                sourceFetcher: fetcher,
                updateSourcePreference: { preference }
            )

            let result = try await service.checkForUpdate(mode: .manual)
            guard case .available = result else {
                XCTFail("Pinned source should produce an available update")
                return
            }
            let expectedCalls = await fetcher.manifestCallCount(for: expectedProvider)
            XCTAssertEqual(expectedCalls, 1)
            let other: UpdateAsset.Provider = expectedProvider == .github ? .gitee : .github
            let otherCalls = await fetcher.manifestCallCount(for: other)
            XCTAssertEqual(otherCalls, 0, "Pinned source must never consult the other source")
            let apiCalls = await fetcher.apiCallCount
            XCTAssertEqual(apiCalls, 0)
        }
    }

    private func runPreparePreferencePinsSource() async throws {
        // GitHub pinned: even an availability failure must not fall back.
        let pinnedGithub = FakeAssetPreparer(results: [
            .github: .availability(.timedOut),
            .gitee: .success
        ])
        let githubService = AppUpdateService(
            assetPreparer: { asset, update in
                try await pinnedGithub.prepare(asset: asset, update: update)
            },
            updateSourcePreference: { .github }
        )
        do {
            _ = try await githubService.prepare(makeUpdateWithGitHubAndGiteeAssets())
            XCTFail("Pinned GitHub failure should not fall back to Gitee")
        } catch is UpdateSourceAvailabilityError {
            let attempts = await pinnedGithub.attempts
            XCTAssertEqual(attempts, [.github])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Gitee pinned: only the Gitee asset is tried.
        let pinnedGitee = FakeAssetPreparer(results: [
            .github: .success,
            .gitee: .success
        ])
        let giteeService = AppUpdateService(
            assetPreparer: { asset, update in
                try await pinnedGitee.prepare(asset: asset, update: update)
            },
            updateSourcePreference: { .gitee }
        )
        _ = try await giteeService.prepare(makeUpdateWithGitHubAndGiteeAssets())
        let giteeAttempts = await pinnedGitee.attempts
        XCTAssertEqual(giteeAttempts, [.gitee])
    }

    private func runPreparePreferenceWithoutAssetReportsUnavailable() async throws {
        let service = AppUpdateService(
            assetPreparer: { asset, update in
                throw UpdateSourceAvailabilityError.resourceUnavailable
            },
            updateSourcePreference: { .gitee }
        )
        do {
            _ = try await service.prepare(makeAvailableUpdate("99.9.9", provider: .github))
            XCTFail("Pinned Gitee without a Gitee asset should fail")
        } catch AppUpdateError.noCompatibleAsset {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    private func runStorePreferencePersists() {
        let suite = "AppUpdateStorePreference-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // The stub checker keeps the preference-change re-check off the network.
        let checker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let store = AppUpdateStore(checking: checker, defaults: defaults)
        XCTAssertEqual(store.updateSourcePreference, .automatic)
        store.setUpdateSourcePreference(.gitee)
        XCTAssertEqual(store.updateSourcePreference, .gitee)
        XCTAssertEqual(defaults.string(forKey: UpdateSourcePreference.storageKey), "gitee")

        let reloaded = AppUpdateStore(checking: checker, defaults: defaults)
        XCTAssertEqual(reloaded.updateSourcePreference, .gitee)
    }

    @MainActor
    private func runStorePreferenceChangeDiscardsStaleResultAndRechecks() async {
        let suite = "AppUpdateStorePreference-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // An automatic check discovers a GitHub-only update.
        let checker = StubUpdateChecker(result: .success(.available(
            makeAvailableUpdate("99.9.9", provider: .github), notes: nil
        )))
        let store = AppUpdateStore(checking: checker, defaults: defaults)
        store.check()
        _ = await waitUntil { store.state == .available }
        XCTAssertNotNil(store.latestUpdate)

        // Pinning a different source must discard that stale result (its
        // update may lack the new source's asset) and run a fresh manual
        // check against the pinned source.
        store.setUpdateSourcePreference(.gitee)
        XCTAssertEqual(store.state, .checking)
        XCTAssertNil(store.latestUpdate)
        _ = await waitUntil { store.state == .available }
        let modes = await checker.modes
        XCTAssertEqual(modes, [.manual, .manual])
    }

    @MainActor
    func testStaleAutomaticCommitIsDiscardedAfterSourceSwitch() async {
        let suite = "AppUpdateStoreRevision-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // The re-check after a source switch reports up-to-date, so the
        // stale automatic commit is only detectable if it is discarded.
        let checker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let store = AppUpdateStore(checking: checker, defaults: defaults)

        // An automatic check started under revision 0 commits successfully.
        XCTAssertEqual(store.commitAutomaticUpdate(
            release: makeRelease("99.9.9"),
            notes: nil,
            expectedSourceRevision: 0
        ), .committed)
        XCTAssertEqual(store.state, .available)
        XCTAssertEqual(store.latestUpdate?.version, "99.9.9")

        // The user pins a source: the store clears the stale result, bumps
        // the revision, and re-checks (ending up-to-date).
        store.setUpdateSourcePreference(.gitee)
        XCTAssertEqual(store.updateSourceRevision, 1)
        _ = await waitUntil { store.state == .upToDate }
        XCTAssertEqual(store.latestUpdate?.version, "2.7.1")

        // The old automatic result arrives late under revision 0: it must be
        // discarded, leaving the newer up-to-date state untouched.
        XCTAssertEqual(store.commitAutomaticUpdate(
            release: makeRelease("99.9.9"),
            notes: nil,
            expectedSourceRevision: 0
        ), .staleSource)
        XCTAssertEqual(store.state, .upToDate)
        XCTAssertEqual(store.latestUpdate?.version, "2.7.1")

        // A commit under the current revision still works.
        XCTAssertEqual(store.commitAutomaticUpdate(
            release: makeRelease("99.9.9"),
            notes: nil,
            expectedSourceRevision: store.updateSourceRevision
        ), .committed)
        XCTAssertEqual(store.state, .available)

        // A commit while an install is in flight reports .busy.
        store.installLauncher = { _ in }
        store.installLatest() // moves state to .downloading synchronously
        XCTAssertEqual(store.commitAutomaticUpdate(
            release: makeRelease("99.9.9"),
            notes: nil,
            expectedSourceRevision: store.updateSourceRevision
        ), .busy)
    }

    private func runGitHubSlowDownloadFallsBackToGiteeAndCaches() async throws {
        let preparer = FakeAssetPreparer(results: [
            .github: .downloadTooSlow,
            .gitee: .success
        ])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        // 第一次：GitHub 慢 → 切 Gitee，成功
        _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
        var attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.github, .gitee])

        // 第二次：30 分钟下载缓存生效，直接 Gitee 优先，不再重测 GitHub
        _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
        attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.github, .gitee, .gitee])
    }

    private func runGitHubSlowWithoutGiteeAssetReportsUnavailable() async throws {
        let preparer = FakeAssetPreparer(results: [.github: .downloadTooSlow])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        do {
            _ = try await service.prepare(makeAvailableUpdate("99.9.9", provider: .github))
            XCTFail("Slow GitHub without a mirror should report unavailable")
        } catch AppUpdateError.updateSourcesUnavailable {
            let attempts = await preparer.attempts
            XCTAssertEqual(attempts, [.github])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func runGitHubSlowAndGiteeFailsDoesNotCache() async throws {
        let preparer = FakeAssetPreparer(results: [
            .github: .downloadTooSlow,
            .gitee: .availability(.httpStatus(503))
        ])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        for _ in 0..<2 {
            do {
                _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
                XCTFail("Both sources failing should be reported")
            } catch AppUpdateError.updateSourcesUnavailable {
                // 切换未成功 → 缓存未写 → 每次仍从 GitHub 开始
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        let attempts = await preparer.attempts
        XCTAssertEqual(attempts, [.github, .gitee, .github, .gitee])
    }

    private func runGitHubSlowAndGiteeIntegrityFailureStops() async throws {
        let preparer = FakeAssetPreparer(results: [
            .github: .downloadTooSlow,
            .gitee: .checksumMismatch
        ])
        let service = AppUpdateService(assetPreparer: { asset, update in
            try await preparer.prepare(asset: asset, update: update)
        })

        do {
            _ = try await service.prepare(makeUpdateWithGitHubAndGiteeAssets())
            XCTFail("Gitee integrity failure should stop, not loop")
        } catch AppUpdateError.checksumMismatch {
            let attempts = await preparer.attempts
            XCTAssertEqual(attempts, [.github, .gitee])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamDownloadSlowTransferThrowsDownloadTooSlow() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let policy = DownloadSourcePolicy(
            minimumRateBytesPerSecond: 50 * 1024,
            observationWindow: 1,
            sampleInterval: 0.1
        )
        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            downloadSourcePolicy: policy
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-SlowDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        // 64KB at 8KB/0.4s ≈ 20KB/s, well below the 50KB/s threshold.
        let body = Data(repeating: 0xAA, count: 64 * 1024)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            UpdateStreamURLProtocol.stopCount = 0
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body
        UpdateStreamURLProtocol.chunkSize = 8 * 1024
        UpdateStreamURLProtocol.chunkInterval = 0.4
        let stopsBefore = UpdateStreamURLProtocol.stopCount
        do {
            _ = try await service.streamDownload(
                URLRequest(url: url),
                to: destination,
                expectedBytes: Int64(body.count),
                slowSpeedPolicy: policy
            )
            XCTFail("A throttled transfer should trigger the slow monitor")
        } catch let error as UpdateSourceAvailabilityError {
            XCTAssertEqual(error, .downloadTooSlow)
            // The transfer really started and was torn down by the switch:
            // URLSession cancels the protocol once the monitor aborts. That
            // teardown is asynchronous — URLSession delivers stopLoading on
            // its own queue — so wait briefly instead of reading the counter
            // the instant the monitor throws (flaky on loaded CI runners).
            let stopDeadline = Date().addingTimeInterval(2)
            while UpdateStreamURLProtocol.stopCount <= stopsBefore, Date() < stopDeadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertGreaterThan(
                UpdateStreamURLProtocol.stopCount,
                stopsBefore,
                "The slow transfer should have been cancelled"
            )
            // The destination file was created before any byte arrived.
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamDownloadNormalSpeedWithPolicySucceeds() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let policy = DownloadSourcePolicy(
            minimumRateBytesPerSecond: 50 * 1024,
            observationWindow: 1,
            sampleInterval: 0.05
        )
        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            downloadSourcePolicy: policy
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-FastDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        let body = Data(repeating: 0xBB, count: 256 * 1024)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            try? FileManager.default.removeItem(at: directory)
        }

        // 全量即时投递：窗口内速率远超阈值，不触发慢速监控
        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body
        let response = try await service.streamDownload(
            URLRequest(url: url),
            to: destination,
            expectedBytes: Int64(body.count),
            slowSpeedPolicy: policy
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }

    func testStreamDownloadExternalCancellationIsNotSwallowedAsSuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let service = AppUpdateService(session: URLSession(configuration: configuration))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-CancelDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        let body = Data(repeating: 0xCC, count: 256 * 1024)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            UpdateStreamURLProtocol.stopCount = 0
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body
        UpdateStreamURLProtocol.chunkSize = 32 * 1024
        UpdateStreamURLProtocol.chunkInterval = 0.1

        let task = Task {
            try await service.streamDownload(URLRequest(url: url), to: destination)
        }
        // Wait until bytes are on disk, then cancel the outer task mid-stream.
        for _ in 0..<50 {
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber
            if (size?.intValue ?? 0) > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("External cancellation must abort the download, not report success")
        } catch is CancellationError {
            // The writer aborts via structured cancellation.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession surfaces the cancellation as URLError(.cancelled).
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamDownloadSlowButShortTransferCompletesBeforeWindowFills() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let policy = DownloadSourcePolicy(
            minimumRateBytesPerSecond: 50 * 1024,
            observationWindow: 10,
            sampleInterval: 0.1
        )
        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            downloadSourcePolicy: policy
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-ShortSlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        // 64KB at ~20KB/s takes ~3.2s, well inside the 10s observation
        // window: the window never fills, so the transfer completes instead
        // of being judged slow.
        let body = Data(repeating: 0xDD, count: 64 * 1024)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body
        UpdateStreamURLProtocol.chunkSize = 8 * 1024
        UpdateStreamURLProtocol.chunkInterval = 0.4
        let response = try await service.streamDownload(
            URLRequest(url: url),
            to: destination,
            expectedBytes: Int64(body.count),
            slowSpeedPolicy: policy
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }

    func testStreamDownloadReportsProgressAndFinalCompletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let service = AppUpdateService(session: URLSession(configuration: configuration))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-ProgressDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        // 100KB in 16KB chunks every 50ms: several marks land outside the
        // 100ms snapshot throttle, so the callback sees real advancement.
        let body = Data(repeating: 0xAB, count: 100 * 1024)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body
        UpdateStreamURLProtocol.chunkSize = 16 * 1024
        UpdateStreamURLProtocol.chunkInterval = 0.05

        let collector = ProgressCollector()
        let response = try await service.streamDownload(
            URLRequest(url: url),
            to: destination,
            expectedBytes: Int64(body.count),
            provider: .github,
            progressHandler: { event in
                await collector.append(event)
            }
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: destination), body)

        // The service flushes the reporting side path before returning, so
        // the collector is complete and in order.
        let events = await collector.events
        let snapshots = progressEvents(events)
        XCTAssertFalse(snapshots.isEmpty, "The transfer must report progress")
        XCTAssertEqual(events.last, .downloadCompleted)
        XCTAssertEqual(snapshots.first?.provider, .github)
        XCTAssertEqual(snapshots.first?.totalBytes, Int64(body.count))
        for (previous, current) in zip(snapshots, snapshots.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                current.receivedBytes,
                previous.receivedBytes,
                "Progress bytes must be monotonic"
            )
        }
        // The final snapshot is emitted unconditionally: even when the
        // throttle suppressed the last mark, the UI sees 100%.
        XCTAssertEqual(snapshots.last?.receivedBytes, Int64(body.count))
        XCTAssertEqual(snapshots.last?.fractionCompleted, 1.0)
    }

    func testStreamDownloadProgressCarriesProvider() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let service = AppUpdateService(session: URLSession(configuration: configuration))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-ProviderProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let body = Data("provider fixture".utf8)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body

        let githubEvents = ProgressCollector()
        _ = try await service.streamDownload(
            URLRequest(url: URL(string: "https://updates.example.com/github.dmg")!),
            to: directory.appendingPathComponent("github.dmg"),
            expectedBytes: Int64(body.count),
            provider: .github,
            progressHandler: { await githubEvents.append($0) }
        )
        let giteeEvents = ProgressCollector()
        _ = try await service.streamDownload(
            URLRequest(url: URL(string: "https://updates.example.com/gitee.dmg")!),
            to: directory.appendingPathComponent("gitee.dmg"),
            expectedBytes: Int64(body.count),
            provider: .gitee,
            progressHandler: { await giteeEvents.append($0) }
        )

        let githubProviders = await githubEvents.events.compactMap { event -> UpdateAsset.Provider? in
            guard case .progress(let progress) = event else { return nil }
            return progress.provider
        }
        let giteeProviders = await giteeEvents.events.compactMap { event -> UpdateAsset.Provider? in
            guard case .progress(let progress) = event else { return nil }
            return progress.provider
        }
        XCTAssertFalse(githubProviders.isEmpty, "A GitHub asset download must report progress")
        XCTAssertFalse(giteeProviders.isEmpty, "A Gitee asset download must report progress")
        XCTAssertTrue(
            githubProviders.allSatisfy { $0 == .github },
            "A GitHub asset download must report .github progress"
        )
        XCTAssertTrue(
            giteeProviders.allSatisfy { $0 == .gitee },
            "A Gitee asset download must report .gitee progress"
        )
    }

    func testSlowUIHandlerDoesNotBlockTheDownloader() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let service = AppUpdateService(session: URLSession(configuration: configuration))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-SlowHandler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("update.dmg")
        let url = URL(string: "https://updates.example.com/YuanGUI.dmg")!
        let body = Data(repeating: 0xAE, count: 64 * 1024)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            try? FileManager.default.removeItem(at: directory)
        }

        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = body

        // A UI handler that sleeps far longer than the whole transfer must
        // not gate the downloader: the writer only yields snapshots, so a
        // busy MainActor can neither stall the transfer nor slow it enough
        // to trip the sustained-slow GitHub → Gitee monitor. The file must
        // be fully written within one handler sleep.
        let task = Task {
            try await service.streamDownload(
                URLRequest(url: url),
                to: destination,
                expectedBytes: Int64(body.count),
                progressHandler: { _ in
                    try? await Task.sleep(for: .seconds(0.5))
                }
            )
        }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber
            if (size?.intValue ?? 0) >= body.count { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber
        XCTAssertEqual(
            finalSize?.intValue,
            body.count,
            "The transfer must complete even while the UI handler is slow"
        )
        _ = try await task.value
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }

    func testAutomaticFallbackRestartsProgressFromZero() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let policy = DownloadSourcePolicy(
            minimumRateBytesPerSecond: 50 * 1024,
            observationWindow: 1,
            sampleInterval: 0.1
        )
        let service = AppUpdateService(
            session: URLSession(configuration: configuration),
            downloadSourcePolicy: policy
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-FallbackProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
            UpdateStreamURLProtocol.urlOverrides = [:]
            try? FileManager.default.removeItem(at: directory)
        }

        // GitHub: delivered at ~20KB/s so the sustained-slow monitor fires
        // and aborts mid-file. Gitee: delivered immediately; its checksum is
        // deliberately wrong so the prepared update fails deterministically
        // right after the download instead of mounting a fake DMG.
        let githubURL = URL(string: "https://updates.example.com/github.dmg")!
        let giteeURL = URL(string: "https://updates.example.com/gitee.dmg")!
        let githubBody = Data(repeating: 0xAC, count: 256 * 1024)
        let giteeBody = Data(repeating: 0xAD, count: 64 * 1024)
        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.urlOverrides = [
            githubURL.absoluteString: UpdateStreamURLProtocol.URLDelivery(
                body: githubBody, chunkSize: 8 * 1024, chunkInterval: 0.4
            ),
            giteeURL.absoluteString: UpdateStreamURLProtocol.URLDelivery(
                body: giteeBody, chunkSize: 0, chunkInterval: 0
            )
        ]
        let update = AvailableUpdate(
            version: "99.9.9",
            build: 17,
            minimumSystemVersion: "15.0",
            publishedAt: Date(timeIntervalSince1970: 1_754_000_000),
            localizedHighlights: ["fixture"],
            releasePageURL: URL(string: "https://github.com/YangChen-cn/yuangui/releases/tag/v99.9.9"),
            assets: [
                UpdateAsset(
                    provider: .github,
                    downloadURL: githubURL,
                    sha256: String(repeating: "a", count: 64),
                    size: Int64(githubBody.count)
                ),
                UpdateAsset(
                    provider: .gitee,
                    downloadURL: giteeURL,
                    sha256: String(repeating: "b", count: 64),
                    size: Int64(giteeBody.count)
                )
            ],
            metadataSource: .manifest(
                URL(string: "https://raw.githubusercontent.com/YangChen-cn/yuangui/main/updates/latest.json")!,
                provider: .github
            )
        )

        let collector = ProgressCollector()
        do {
            _ = try await service.prepare(update) { event in
                await collector.append(event)
            }
            XCTFail("The mismatched Gitee checksum must stop the update")
        } catch AppUpdateError.checksumMismatch {
            // Each attempt's reporting side path is flushed before it returns
            // or throws, so no stale GitHub snapshot can leak into the Gitee
            // event sequence.
            let events = await collector.events
            let snapshots = progressEvents(events)
            let githubSnapshots = snapshots.filter { $0.provider == .github }
            let giteeSnapshots = snapshots.filter { $0.provider == .gitee }
            XCTAssertFalse(githubSnapshots.isEmpty, "The GitHub attempt must report progress")
            XCTAssertFalse(giteeSnapshots.isEmpty, "The Gitee fallback must report progress")
            // All GitHub snapshots precede the first Gitee snapshot.
            let firstGitee = snapshots.firstIndex { $0.provider == .gitee } ?? snapshots.count
            let lastGithub = snapshots.lastIndex { $0.provider == .github } ?? -1
            XCTAssertLessThan(lastGithub, firstGitee, "Provider order must be .github then .gitee")
            // GitHub was aborted mid-file; Gitee started fresh from a small
            // byte count and ran to completion with its own total.
            XCTAssertLessThan(githubSnapshots.last?.fractionCompleted ?? 1, 1)
            XCTAssertLessThan(giteeSnapshots.first?.receivedBytes ?? 0, Int64(giteeBody.count))
            XCTAssertEqual(giteeSnapshots.last?.receivedBytes, Int64(giteeBody.count))
            XCTAssertEqual(giteeSnapshots.last?.fractionCompleted, 1.0)
            // Only the winning attempt signals transfer completion; the
            // aborted GitHub attempt never does.
            XCTAssertTrue(events.contains(.downloadCompleted))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadProgressTrackerSlidingWindow() async {
        let clock = FakeClock(startingAt: Date(timeIntervalSince1970: 1_000))
        let tracker = DownloadProgressTracker(now: { clock.now() })

        // 窗口未满 → 不判定
        await tracker.markProgress(bytes: 0)
        clock.advance(by: 0.5)
        await tracker.markProgress(bytes: 8 * 1024)
        let notYet = await tracker.isSlow(under: 50 * 1024, window: 10)
        XCTAssertFalse(notYet, "Window not full yet must not judge")

        // 持续低速：10 秒内平均 10KB/s < 50KB/s → 触发
        clock.advance(by: 1)
        await tracker.markProgress(bytes: 16 * 1024)
        clock.advance(by: 1)
        await tracker.markProgress(bytes: 24 * 1024)
        clock.advance(by: 1)
        await tracker.markProgress(bytes: 32 * 1024)
        clock.advance(by: 7)
        await tracker.markProgress(bytes: 102 * 1024)
        let slow = await tracker.isSlow(under: 50 * 1024, window: 10)
        XCTAssertTrue(slow, "10s average of ~10KB/s must trigger")

        // 突发拉高窗口平均 → 不触发
        let burstTracker = DownloadProgressTracker(now: { clock.now() })
        await burstTracker.markProgress(bytes: 0)
        clock.advance(by: 2)
        await burstTracker.markProgress(bytes: 2 * 1024 * 1024) // 前 2s 突发 2MB
        clock.advance(by: 8)
        await burstTracker.markProgress(bytes: 2 * 1024 * 1024 + 8 * 1024) // 后 8s 极慢
        let burst = await burstTracker.isSlow(under: 50 * 1024, window: 10)
        XCTAssertFalse(burst, "Burst average must not trigger")
    }

    func testDownloadProgressTrackerLongSlowTransferStaysSlow() async {
        let clock = FakeClock(startingAt: Date(timeIntervalSince1970: 1_000))
        let tracker = DownloadProgressTracker(now: { clock.now() })

        // Sustained 20KB/s for 60 seconds, sampled every 2s. A first/last
        // comparison divides the whole accumulated history (1.2MB) by the
        // fixed 10s window (120KB/s) and stops reporting slow; the trailing
        // window must stay at ~20KB/s for the whole transfer.
        await tracker.markProgress(bytes: 0)
        var slowFlags: [Bool] = []
        for second in stride(from: 2, through: 60, by: 2) {
            clock.advance(by: 2)
            await tracker.markProgress(bytes: Int64(second) * 20 * 1024)
            if second >= 20 {
                slowFlags.append(await tracker.isSlow(under: 50 * 1024, window: 10))
            }
        }
        XCTAssertFalse(
            slowFlags.contains(false),
            "A constant 20KB/s transfer must be slow at every trailing-window check"
        )
        let finalSlow = await tracker.isSlow(under: 50 * 1024, window: 10)
        XCTAssertTrue(finalSlow)

        // A burst that ends well after the window baseline stays non-slow:
        // pruning must never make a fast transfer look slow retroactively.
        let burstTracker = DownloadProgressTracker(now: { clock.now() })
        await burstTracker.markProgress(bytes: 0)
        clock.advance(by: 2)
        await burstTracker.markProgress(bytes: 2 * 1024 * 1024)
        clock.advance(by: 8)
        await burstTracker.markProgress(bytes: 2 * 1024 * 1024 + 8 * 1024)
        let burstSlow = await burstTracker.isSlow(under: 50 * 1024, window: 10)
        XCTAssertFalse(burstSlow)
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

    func testReleaseNotesAndGitHubDecodeScenarios() async throws {
        try runGitHubReleaseDecodesNotesAndFindsDMG()
        try runGitHubReleaseSelectsLocalizedReleaseNotesAsset()
        try await runManualCheckReturnsCompleteLocalizedReleaseNotes()
        runReleaseNotesKeepGitHubMarkdownStructure()
    }

    private func runGitHubReleaseDecodesNotesAndFindsDMG() throws {
        let data = Data(#"{"tag_name":"v1.0.2","name":"元圭与 VCC 1.0.2","body":"更新日志","html_url":"https://github.com/YangChen-cn/yuangui/releases/tag/v1.0.2","assets":[{"name":"YuanGUI-1.0.2.dmg","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v1.0.2/YuanGUI-1.0.2.dmg","size":1234}]}"#.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        XCTAssertEqual(release.version, "1.0.2")
        XCTAssertEqual(release.body, "更新日志")
        XCTAssertEqual(release.dmgAsset?.name, "YuanGUI-1.0.2.dmg")
    }

    private func runGitHubReleaseSelectsLocalizedReleaseNotesAsset() throws {
        let data = Data(#"{"tag_name":"v2.7.0","name":"YuanGUI 2.7.0","body":"English fallback","html_url":"https://github.com/YangChen-cn/yuangui/releases/tag/v2.7.0","assets":[{"name":"RELEASE_NOTES.md","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v2.7.0/RELEASE_NOTES.md","size":10},{"name":"RELEASE_NOTES.zh-CN.md","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v2.7.0/RELEASE_NOTES.zh-CN.md","size":12}]}"#.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        XCTAssertEqual(release.releaseNotesAsset(for: .english)?.name, "RELEASE_NOTES.md")
        XCTAssertEqual(release.releaseNotesAsset(for: .simplifiedChinese)?.name, "RELEASE_NOTES.zh-CN.md")
        XCTAssertNotNil(release.releaseNotesAsset(for: .system))
    }

    private func runManualCheckReturnsCompleteLocalizedReleaseNotes() async throws {
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

    private func runReleaseNotesKeepGitHubMarkdownStructure() {
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
        XCTAssertTrue(script.contains("pkill -x \"YuanGUIFinderExtension\""))
        XCTAssertTrue(script.contains("pluginkit -a \"$finder_extension\""))
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
    /// Per-URL delivery for mixed-speed scenarios (one slow source, one fast
    /// mirror). When a URL is present here it wins over the static fields.
    struct URLDelivery: Sendable {
        var body: Data
        var chunkSize: Int
        var chunkInterval: TimeInterval
    }

    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    /// When `chunkSize > 0`, the body is delivered in chunks of that size at
    /// `chunkInterval` intervals to simulate a throttled transfer.
    nonisolated(unsafe) static var chunkSize = 0
    nonisolated(unsafe) static var chunkInterval: TimeInterval = 0
    nonisolated(unsafe) static var stopCount = 0
    nonisolated(unsafe) static var urlOverrides: [String: URLDelivery] = [:]

    private var deliveryTask: DispatchWorkItem?

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
        let body: Data
        let chunkSize: Int
        let interval: TimeInterval
        if let override = Self.urlOverrides[url.absoluteString] {
            body = override.body
            chunkSize = override.chunkSize
            interval = override.chunkInterval
        } else {
            body = Self.body
            chunkSize = Self.chunkSize
            interval = Self.chunkInterval
        }
        guard (200..<300).contains(Self.statusCode), !body.isEmpty else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard chunkSize > 0, interval > 0 else {
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.deliverChunks(body, chunkSize: chunkSize, interval: interval, index: 0)
        }
        deliveryTask = work
        DispatchQueue.global().async(execute: work)
    }

    private func deliverChunks(_ body: Data, chunkSize: Int, interval: TimeInterval, index: Int) {
        let start = index * chunkSize
        guard start < body.count else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let end = min(start + chunkSize, body.count)
        client?.urlProtocol(self, didLoad: body.subdata(in: start..<end))
        let work = DispatchWorkItem { [weak self] in
            self?.deliverChunks(body, chunkSize: chunkSize, interval: interval, index: index + 1)
        }
        deliveryTask = work
        DispatchQueue.global().asyncAfter(deadline: .now() + interval, execute: work)
    }

    override func stopLoading() {
        Self.stopCount += 1
        deliveryTask?.cancel()
        deliveryTask = nil
    }
}
import XCTest
@testable import YuanGUI

private struct TestError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Thread-safe fake clock for the download-rate tracker's sliding window.
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(startingAt date: Date) {
        current = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}

/// Collects transfer lifecycle events from an async callback in call order.
private actor ProgressCollector {
    private(set) var events: [UpdateDownloadEvent] = []

    func append(_ event: UpdateDownloadEvent) {
        events.append(event)
    }
}

/// The `.progress` payloads from a collected event sequence.
private func progressEvents(_ events: [UpdateDownloadEvent]) -> [UpdateDownloadProgress] {
    events.compactMap { event in
        guard case .progress(let progress) = event else { return nil }
        return progress
    }
}

private actor StubUpdateChecker: UpdateChecking {
    let result: Result<UpdateCheckResult, TestError>
    /// Optional suspension so a test can interleave a source switch while
    /// the automatic check is still in flight.
    private let delay: Duration
    private(set) var callCount = 0
    private(set) var modes: [UpdateCheckMode] = []

    init(result: Result<UpdateCheckResult, TestError>, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    func checkForUpdate() async throws -> UpdateCheckResult {
        try await checkForUpdate(mode: .automatic)
    }

    func checkForUpdate(mode: UpdateCheckMode) async throws -> UpdateCheckResult {
        callCount += 1
        modes.append(mode)
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

private final class MutableDateProvider {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private final class Counter {
    var count = 0
}

private final class LogCollector {
    private(set) var messages: [String] = []
    func append(_ message: String) { messages.append(message) }
}

private final class FakeNetworkStatus: UpdateNetworkStatusProviding, @unchecked Sendable {
    var offline = false
    func isClearlyOffline() -> Bool { offline }
}

@MainActor
private final class FakeUpdatePromptEnvironment: UpdatePromptEnvironment {
    var isApplicationActive = true
    var hasBlockingModalPresentation = false
}

@MainActor
private final class FakeUpdatePromptPresenter: UpdatePromptPresenting {
    private(set) var isPresenting = false
    private(set) var presentCount = 0
    private(set) var lastRelease: AvailableUpdate?
    private(set) var lastHighlights: [String] = []
    private var installAction: (() -> Void)?
    private var laterAction: (() -> Void)?
    private var detailsAction: (() -> Void)?

    func presentUpdate(
        currentVersion: String,
        update: AvailableUpdate,
        highlights: [String],
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onShowDetails: @escaping () -> Void
    ) {
        guard !isPresenting else { return }
        presentCount += 1
        isPresenting = true
        lastRelease = update
        lastHighlights = highlights
        installAction = onInstall
        laterAction = onLater
        detailsAction = onShowDetails
    }

    func dismiss() {
        dismiss(choosingInstall: false)
    }

    func dismiss(choosingInstall: Bool) {
        guard isPresenting else { return }
        isPresenting = false
        if choosingInstall {
            installAction?()
        } else {
            laterAction?()
        }
    }

    func chooseDetails() {
        guard isPresenting else { return }
        isPresenting = false
        detailsAction?()
    }
}

@MainActor
private struct Fixture {
    let coordinator: AutomaticUpdateCheckCoordinator
    let store: AppUpdateStore
    let presenter: FakeUpdatePromptPresenter
    let checker: StubUpdateChecker
    let defaults: UserDefaults
    let provider: MutableDateProvider
    let installCount: Counter
    let detailsCount: Counter
    let logs: LogCollector
    let environment: FakeUpdatePromptEnvironment
    let network: FakeNetworkStatus
    let suite: String

    static func make(
        result: Result<UpdateCheckResult, TestError>,
        store: AppUpdateStore? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        startupDelay: Duration = .zero,
        willPresentPrompt: @escaping () -> Void = {}
    ) -> Fixture {
        let suite = "AutomaticUpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let checker = StubUpdateChecker(result: result)
        let store = store ?? AppUpdateStore()
        let presenter = FakeUpdatePromptPresenter()
        let environment = FakeUpdatePromptEnvironment()
        let provider = MutableDateProvider(now)
        let installCount = Counter()
        let detailsCount = Counter()
        let logs = LogCollector()
        let network = FakeNetworkStatus()
        let coordinator = AutomaticUpdateCheckCoordinator(
            checker: checker,
            store: store,
            presenter: presenter,
            environment: environment,
            networkStatus: network,
            defaults: defaults,
            calendar: calendar,
            now: { provider.now },
            startupDelay: startupDelay,
            install: { installCount.count += 1 },
            showDetails: { detailsCount.count += 1 },
            willPresentPrompt: willPresentPrompt,
            log: { logs.append($0) }
        )
        return Fixture(
            coordinator: coordinator,
            store: store,
            presenter: presenter,
            checker: checker,
            defaults: defaults,
            provider: provider,
            installCount: installCount,
            detailsCount: detailsCount,
            logs: logs,
            environment: environment,
            network: network,
            suite: suite
        )
    }

    func cleanup() {
        coordinator.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private func makeRelease(_ version: String, build: Int? = nil, body: String? = nil) -> AvailableUpdate {
    let notes = body ?? "Release notes for \(version)"
    return AvailableUpdate(
        version: version,
        build: build,
        minimumSystemVersion: nil,
        publishedAt: nil,
        localizedHighlights: UpdateHighlightExtractor.highlights(from: notes),
        releasePageURL: URL(string: "https://github.com/YangChen-cn/yuangui/releases/tag/v\(version)"),
        assets: [],
        metadataSource: .githubReleaseAPI
    )
}

@MainActor
private func makeDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int, _ minute: Int, _ second: Int,
    calendar: Calendar
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
}

@MainActor
private func waitUntil(
    _ condition: @escaping () -> Bool,
    timeout: TimeInterval = 2
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@MainActor
private func waitForCallCount(
    _ checker: StubUpdateChecker,
    _ expected: Int,
    timeout: TimeInterval = 2
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if await checker.callCount >= expected { return true }
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
final class AutomaticUpdateTests: XCTestCase {

    // MARK: - Daily limit

    func testAutomaticDailyPolicyScenarios() async {
        await runFirstAutomaticTriggerChecksAndPromptsForAvailable()
        await runSecondAutomaticTriggerSameDayIsSkipped()
        await runRecreatedCoordinatorSameDayDoesNotCheckAgain()
        await runNextNaturalDayChecksAgain()
        await runTimeZoneDayBoundaryIsHandledByCalendar()
        await runConcurrentTriggersProduceOnlyOneRequest()
    }

    private func runFirstAutomaticTriggerChecksAndPromptsForAvailable() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "notes")))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        let modes = await fixture.checker.modes
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(modes, [.automatic])
        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertEqual(fixture.store.state, .available)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.check.started"))
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.prompt.presented"))
    }

    private func runSecondAutomaticTriggerSameDayIsSkipped() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.coordinator.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.alreadyChecked"))
    }

    private func runRecreatedCoordinatorSameDayDoesNotCheckAgain() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        // A brand new coordinator sharing the same defaults must respect the
        // persisted "checked today" marker.
        let secondChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let secondPresenter = FakeUpdatePromptPresenter()
        let second = AutomaticUpdateCheckCoordinator(
            checker: secondChecker,
            store: AppUpdateStore(),
            presenter: secondPresenter,
            defaults: fixture.defaults,
            calendar: .autoupdatingCurrent,
            now: { fixture.provider.now }
        )
        second.runAutomaticCheckIfNeeded()

        let firstCalls = await fixture.checker.callCount
        let secondCalls = await secondChecker.callCount
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 0)
        XCTAssertEqual(secondPresenter.presentCount, 0)
    }

    private func runNextNaturalDayChecksAgain() async {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            now: makeDate(2026, 8, 1, 23, 59, 0, calendar: utc),
            calendar: utc
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        fixture.provider.now = makeDate(2026, 8, 2, 0, 1, 0, calendar: utc)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)
    }

    private func runTimeZoneDayBoundaryIsHandledByCalendar() async {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            now: makeDate(2026, 8, 1, 23, 59, 0, calendar: utc),
            calendar: utc
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        // The marker is persisted as start-of-day; comparing in a second,
        // different calendar must not crash or get permanently stuck. Here the
        // wall-clock day has not changed, so the automatic check stays quiet.
        var pacific = calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let pacificNow = makeDate(2026, 8, 1, 16, 0, 0, calendar: utc)
        let recreated = AutomaticUpdateCheckCoordinator(
            checker: StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1")))),
            store: AppUpdateStore(),
            presenter: FakeUpdatePromptPresenter(),
            defaults: fixture.defaults,
            calendar: pacific,
            now: { pacificNow }
        )
        recreated.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
    }

    private func runConcurrentTriggersProduceOnlyOneRequest() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        fixture.coordinator.runAutomaticCheckIfNeeded()
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
    }

    // MARK: - Manual checks

    func testManualCheckIsNotBlockedByDailyLimit() async {
        // A manual check on the shared store must run even though the
        // automatic coordinator already marked today as checked.
        let storeChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let store = AppUpdateStore(checking: storeChecker)
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            store: store
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        store.check()
        _ = await waitUntil { store.state == .upToDate }

        let manualCalls = await storeChecker.callCount
        let manualModes = await storeChecker.modes
        XCTAssertEqual(manualCalls, 1)
        XCTAssertEqual(manualModes, [.manual])
        XCTAssertEqual(store.state, .upToDate)
    }

    func testSuccessfulManualCheckSuppressesSameDayAutomaticCheck() async {
        let storeChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let store = AppUpdateStore(checking: storeChecker)
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("99.9.9"))),
            store: store
        )
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        store.check()
        _ = await waitUntil { store.state == .upToDate }

        // The manual success marked the day; a follow-up automatic trigger
        // must not hit the network again.
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.alreadyChecked"))
    }

    func testManualCheckErrorStillShowsFailure() async {
        let storeChecker = StubUpdateChecker(result: .failure(TestError(message: "boom")))
        let store = AppUpdateStore(checking: storeChecker)
        store.check()
        _ = await waitUntil {
            if case .failed = store.state { return true }
            return false
        }
        if case .failed(let message) = store.state {
            XCTAssertEqual(message, "boom")
        } else {
            XCTFail("Manual check error should leave the store in failed state")
        }
        XCTAssertNil(store.latestUpdate)
    }

    // MARK: - Prompt behavior

    func testAutomaticPromptEligibilityScenarios() async {
        await runNoPromptWhenUpToDate()
        await runNoPromptWhenLatestIsOlderThanCurrent()
        await runAvailableUpdatePromptsExactlyOnce()
        await runNoSecondPromptWhileOneIsPresented()
        await runPromptPresenterIgnoresSecondPresentation()
    }

    private func runNoPromptWhenUpToDate() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        XCTAssertEqual(fixture.store.state, .idle)
    }

    private func runNoPromptWhenLatestIsOlderThanCurrent() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("1.0.0"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.check.upToDate"))
    }

    private func runAvailableUpdatePromptsExactlyOnce() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertEqual(fixture.store.state, .available)
    }

    private func runNoSecondPromptWhileOneIsPresented() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        XCTAssertTrue(fixture.presenter.isPresenting)

        // A new natural day arrives while the user still has the alert open.
        fixture.provider.now = fixture.provider.now.addingTimeInterval(86_400)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.promptPresented"))
    }

    private func runPromptPresenterIgnoresSecondPresentation() async {
        let presenter = FakeUpdatePromptPresenter()
        presenter.presentUpdate(
            currentVersion: "2.7.1",
            update: makeRelease("99.9.9"),
            highlights: [],
            onInstall: {},
            onLater: {},
            onShowDetails: {}
        )
        presenter.presentUpdate(
            currentVersion: "2.7.1",
            update: makeRelease("99.9.9"),
            highlights: [],
            onInstall: {},
            onLater: {},
            onShowDetails: {}
        )
        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertTrue(presenter.isPresenting)
    }

    func testAutomaticPromptActions() async {
        await runLaterDoesNotStartInstall()
        await runInstallActionRunsExactlyOnce()
        await runLaterSuppressesSameDayAutomaticPrompt()
        await runSameAvailableVersionRemindsAgainNextDay()
        await runDetailsActionKeepsAvailableStoreStateAndRunsOnce()
    }

    private func runLaterDoesNotStartInstall() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        fixture.presenter.dismiss(choosingInstall: false)

        XCTAssertEqual(fixture.installCount.count, 0)
        XCTAssertEqual(fixture.store.state, .available)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.prompt.later"))
        XCTAssertFalse(fixture.logs.messages.contains("update.auto.prompt.install"))
    }

    private func runInstallActionRunsExactlyOnce() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        fixture.presenter.dismiss(choosingInstall: true)
        // Simulate a rapid second activation of the primary action.
        fixture.presenter.dismiss(choosingInstall: true)

        XCTAssertEqual(fixture.installCount.count, 1)
        // Install from the automatic prompt opens the About page first so the
        // download progress is visible there.
        XCTAssertEqual(fixture.detailsCount.count, 1)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.prompt.install"))
    }

    private func runLaterSuppressesSameDayAutomaticPrompt() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.presenter.dismiss(choosingInstall: false)

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
    }

    private func runSameAvailableVersionRemindsAgainNextDay() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.presenter.dismiss(choosingInstall: false)

        fixture.provider.now = fixture.provider.now.addingTimeInterval(86_400)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(fixture.presenter.presentCount, 2)
    }

    // MARK: - Failure and lifecycle

    func testAutomaticFailureAndRetryPolicyScenarios() async {
        await runAutomaticNetworkFailureStaysQuiet()
        await runClearlyOfflineDoesNotStartOrConsumeAnAutomaticAttempt()
        await runAutomaticFailureWaitsFourHoursBeforeRetrying()
        await runAutomaticFailureStopsAtTwoAttemptsAndResetsNextDay()
    }

    private func runAutomaticNetworkFailureStaysQuiet() async {
        let fixture = Fixture.make(result: .failure(TestError(message: "offline")))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        XCTAssertEqual(fixture.store.state, .idle)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.check.failed"))
    }

    private func runClearlyOfflineDoesNotStartOrConsumeAnAutomaticAttempt() async {
        let fixture = Fixture.make(result: .failure(TestError(message: "offline")))
        defer { fixture.cleanup() }
        fixture.network.offline = true

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let initialCalls = await fixture.checker.callCount
        XCTAssertEqual(initialCalls, 0)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateCheckCoordinator.automaticAttemptCountKey))
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateCheckCoordinator.lastSuccessfulAutomaticCheckDayKey))
    }

    private func runAutomaticFailureWaitsFourHoursBeforeRetrying() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let fixture = Fixture.make(
            result: .failure(TestError(message: "offline")),
            now: makeDate(2026, 8, 1, 9, 0, 0, calendar: calendar),
            calendar: calendar
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        var calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.defaults.integer(forKey: AutomaticUpdateCheckCoordinator.automaticAttemptCountKey), 1)

        fixture.provider.now = fixture.provider.now.addingTimeInterval(3.5 * 60 * 60)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)

        fixture.provider.now = fixture.provider.now.addingTimeInterval(30 * 60 + 1)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)
    }

    private func runAutomaticFailureStopsAtTwoAttemptsAndResetsNextDay() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let fixture = Fixture.make(
            result: .failure(TestError(message: "offline")),
            now: makeDate(2026, 8, 1, 9, 0, 0, calendar: calendar),
            calendar: calendar
        )
        defer { fixture.cleanup() }

        for _ in 0..<2 {
            fixture.coordinator.runAutomaticCheckIfNeeded()
            await fixture.coordinator.awaitCurrentCheck()
            fixture.provider.now = fixture.provider.now.addingTimeInterval(4 * 60 * 60 + 1)
        }
        var calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)

        fixture.provider.now = makeDate(2026, 8, 2, 9, 0, 0, calendar: calendar)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 3)
    }

    func testNetworkRecoveryChecksOnNextActiveEvent() async {
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            startupDelay: .zero
        )
        defer { fixture.cleanup() }
        fixture.network.offline = true
        fixture.coordinator.start()
        try? await Task.sleep(for: .milliseconds(30))
        let initialCalls = await fixture.checker.callCount
        XCTAssertEqual(initialCalls, 0)

        fixture.network.offline = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        let didCheck = await waitForCallCount(fixture.checker, 1)
        XCTAssertTrue(didCheck)
    }

    func testStaleAutomaticCheckDoesNotMarkDayChecked() async {
        let suite = "AutomaticUpdateStaleSource-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // The automatic check is slow; while it is in flight the user pins a
        // source (revision 1). The completed stale check must neither publish
        // its result nor mark today as checked.
        let autoChecker = StubUpdateChecker(
            result: .success(.available(makeRelease("99.9.9"), notes: nil)),
            delay: .milliseconds(200)
        )
        let storeChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        // Isolated defaults: .standard may carry a real user preference.
        let store = AppUpdateStore(checking: storeChecker, defaults: defaults)
        let presenter = FakeUpdatePromptPresenter()
        let logs = LogCollector()
        let coordinator = AutomaticUpdateCheckCoordinator(
            checker: autoChecker,
            store: store,
            presenter: presenter,
            environment: FakeUpdatePromptEnvironment(),
            networkStatus: FakeNetworkStatus(),
            defaults: defaults,
            calendar: .autoupdatingCurrent,
            startupDelay: .zero,
            log: { logs.append($0) }
        )
        defer { coordinator.stop() }

        coordinator.runAutomaticCheckIfNeeded()
        // Wait until the check task has actually started: the coordinator
        // captures the source revision right before calling the checker, so
        // callCount == 1 guarantees the capture happened under revision 0.
        _ = await waitForCallCount(autoChecker, 1)
        store.setUpdateSourcePreference(.gitee)
        _ = await waitUntil { store.state == .upToDate }
        await coordinator.awaitCurrentCheck()

        XCTAssertEqual(presenter.presentCount, 0)
        XCTAssertEqual(store.state, .upToDate)
        XCTAssertNil(
            defaults.object(forKey: AutomaticUpdateCheckCoordinator.lastSuccessfulAutomaticCheckDayKey),
            "A stale source result must not mark today as successfully checked"
        )
        XCTAssertTrue(logs.messages.contains("update.auto.skipped.staleSource"))
    }

    func testAutomaticCheckSkippedWhileStoreIsBusy() async {
        let store = AppUpdateStore()
        store.commitAutomaticUpdate(release: makeRelease("99.9.9"), notes: nil, expectedSourceRevision: store.updateSourceRevision)
        store.installLauncher = { _ in }
        store.installLatest() // moves state to .downloading synchronously

        let fixture = Fixture.make(
            result: .success(.available(makeRelease("99.9.9"), notes: nil)),
            store: store
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.busy"))
        _ = await waitUntil { store.state == .installing }
    }

    func testStopLifecycleScenarios() async {
        await runStopPreventsFurtherChecksAndRemovesObserver()
        await runRunAfterStopIsANoOp()
        await runStopDiscardsPendingUpdate()
    }

    private func runStopPreventsFurtherChecksAndRemovesObserver() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        _ = await waitForCallCount(fixture.checker, 1)

        fixture.coordinator.stop()
        // Reset the daily marker so only the observer removal / stopped flag
        // can explain why nothing else fires.
        fixture.defaults.removeObject(forKey: AutomaticUpdateCheckCoordinator.lastSuccessfulAutomaticCheckDayKey)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
    }

    private func runRunAfterStopIsANoOp() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        fixture.coordinator.stop()
        fixture.coordinator.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(fixture.presenter.presentCount, 0)
    }

    // MARK: - Presentation timing and pending state

    func testStartupActivationDoesNotBypassDelayAndChecksOnceAfterwards() async {
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            startupDelay: .milliseconds(120)
        )
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        let earlyCallCount = await fixture.checker.callCount
        XCTAssertEqual(earlyCallCount, 0)

        let didCheck = await waitForCallCount(fixture.checker, 1, timeout: 1)
        XCTAssertTrue(didCheck)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        let finalCallCount = await fixture.checker.callCount
        XCTAssertEqual(finalCallCount, 1)
    }

    func testInactiveApplicationKeepsUpdatePendingUntilNextActivation() async {
        let fixture = Fixture.make(
            result: .success(.available(makeRelease("99.9.9"), notes: "- Faster launch")),
            startupDelay: .zero
        )
        defer { fixture.cleanup() }

        fixture.environment.isApplicationActive = false
        fixture.coordinator.start()
        try? await Task.sleep(for: .milliseconds(20))
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        fixture.environment.isApplicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        let didPresent = await waitUntil { fixture.presenter.presentCount == 1 }
        XCTAssertTrue(didPresent)
    }

    func testExplicitInteractionPresentsPendingUpdateImmediately() async {
        let transientPanelHideCount = Counter()
        let fixture = Fixture.make(
            result: .success(.available(makeRelease("99.9.9"), notes: "- Faster launch")),
            startupDelay: .zero,
            willPresentPrompt: { transientPanelHideCount.count += 1 }
        )
        defer { fixture.cleanup() }

        fixture.environment.isApplicationActive = false
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        XCTAssertEqual(fixture.presenter.presentCount, 0)

        fixture.environment.isApplicationActive = true
        fixture.coordinator.handleExplicitUserInteraction()

        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertEqual(transientPanelHideCount.count, 1)
    }

    func testExplicitInteractionStartsAutomaticCheckWhenApplicationIsActive() async {
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            startupDelay: .zero
        )
        defer { fixture.cleanup() }

        fixture.coordinator.handleExplicitUserInteraction()
        await fixture.coordinator.awaitCurrentCheck()

        let callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testExplicitInteractionDoesNotStartDuringBlockingModalPresentation() async {
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            startupDelay: .zero
        )
        defer { fixture.cleanup() }

        fixture.environment.hasBlockingModalPresentation = true
        fixture.coordinator.handleExplicitUserInteraction()
        await Task.yield()

        let callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testBlockingModalDefersPromptUntilSheetEnds() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "- Safer updates")))
        defer { fixture.cleanup() }

        fixture.environment.hasBlockingModalPresentation = true
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        XCTAssertEqual(fixture.presenter.presentCount, 0)

        fixture.environment.hasBlockingModalPresentation = false
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: nil)
        fixture.coordinator.tryPresentPendingUpdate()
        XCTAssertEqual(fixture.presenter.presentCount, 1)
    }

    private func runStopDiscardsPendingUpdate() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "- Deferred")))
        defer { fixture.cleanup() }

        fixture.environment.isApplicationActive = false
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.coordinator.stop()
        fixture.environment.isApplicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
    }

    func testManualAvailableResultDoesNotOpenAutomaticPrompt() async {
        let checker = StubUpdateChecker(
            result: .success(.available(makeRelease("99.9.9"), notes: "- Manual result"))
        )
        let store = AppUpdateStore(checking: checker)
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            store: store
        )
        defer { fixture.cleanup() }

        store.check()
        let becameAvailable = await waitUntil { store.state == .available }
        XCTAssertTrue(becameAvailable)
        XCTAssertEqual(fixture.presenter.presentCount, 0)
    }

    private func runDetailsActionKeepsAvailableStoreStateAndRunsOnce() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "- Details")))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.presenter.chooseDetails()
        fixture.presenter.chooseDetails()

        XCTAssertEqual(fixture.detailsCount.count, 1)
        XCTAssertEqual(fixture.store.state, .available)
    }

    // MARK: - Prompt content and geometry

    func testHighlightsPreferBulletsAndSkipReleaseHeading() {
        let release = makeRelease(
            "2.7.2",
            body: "## YuanGUI 2.7.2\n\n- **Faster** dashboard refresh\n- Added `View Details` action\n- This third item is not shown"
        )

        XCTAssertEqual(
            AutomaticUpdateCheckCoordinator.highlights(for: release, notes: nil),
            ["Faster dashboard refresh", "Added View Details action"]
        )
    }

    func testHighlightsReturnEmptyForEmptyOrHeadingOnlyNotes() {
        XCTAssertEqual(
            AutomaticUpdateCheckCoordinator.highlights(for: makeRelease("2.7.2", body: ""), notes: nil),
            []
        )
        XCTAssertEqual(
            AutomaticUpdateCheckCoordinator.highlights(for: makeRelease("2.7.2", body: "# 2.7.2"), notes: nil),
            []
        )
    }

    func testPromptPlacementCentersWithinVisibleFrameAndClampsSize() {
        let visibleFrame = CGRect(x: -1280, y: 23, width: 1920, height: 1057)
        let frame = UpdatePromptWindowPlacement.centeredFrame(
            windowSize: CGSize(width: 900, height: 900),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.size, CGSize(width: 500, height: 360))
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testPromptPlacementHandlesVerticalMonitorAndDockOffset() {
        let visibleFrame = CGRect(x: 0, y: 1080, width: 1440, height: 900)
        let origin = UpdatePromptWindowPlacement.centeredOrigin(
            windowSize: CGSize(width: 460, height: 300),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 490, accuracy: 0.001)
        XCTAssertEqual(origin.y, 1380, accuracy: 0.001)
    }

    // MARK: - Store install guard

    func testInstallLatestRespectsBuildNumber() async {
        let currentVersion = AppVersionInfo.version
        let currentBuild = Int(AppVersionInfo.build) ?? 0

        // Same version with a higher build is a repair update and installs.
        let store = AppUpdateStore()
        var installCount = 0
        store.installLauncher = { _ in installCount += 1 }
        store.commitAutomaticUpdate(release: makeRelease(currentVersion, build: currentBuild + 1), notes: nil, expectedSourceRevision: store.updateSourceRevision)
        store.installLatest()
        _ = await waitUntil { store.state == .installing }
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(store.state, .installing)

        // Same version with an equal (or missing) build is already current
        // and must not start an install even when the button is reachable.
        let store2 = AppUpdateStore()
        var installCount2 = 0
        store2.installLauncher = { _ in installCount2 += 1 }
        store2.commitAutomaticUpdate(release: makeRelease(currentVersion, build: currentBuild), notes: nil, expectedSourceRevision: store2.updateSourceRevision)
        store2.installLatest()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(installCount2, 0)
        XCTAssertEqual(store2.state, .available)
    }

    func testInstallLatestIgnoresRapidRepeatedClicks() async {
        let store = AppUpdateStore()
        var installCount = 0
        store.installLauncher = { _ in installCount += 1 }
        store.commitAutomaticUpdate(release: makeRelease("99.9.9"), notes: nil, expectedSourceRevision: store.updateSourceRevision)

        store.installLatest()
        store.installLatest() // second click is ignored while the first runs

        _ = await waitUntil { store.state == .installing }
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(store.state, .installing)
        XCTAssertNil(store.downloadProgress)
    }

    @MainActor
    func testInstallLatestPublishesProgressAndClearsOnFailure() async throws {
        let suite = "AppUpdateStoreProgress-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Real streamed download through the URLProtocol seam: the fixture
        // body fails asset-size verification (expected 1024), so the install
        // ends in .failed. The transfer is throttled so progress publishing
        // is observable. The .installing phase on transfer completion lasts
        // microseconds (verification fails immediately), so it is captured
        // through the store's own publisher instead of polling: every
        // transition is recorded synchronously.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStreamURLProtocol.self]
        let service = AppUpdateService(session: URLSession(configuration: configuration))
        let store = AppUpdateStore(service: service, defaults: defaults)
        var observedStates: [AppUpdateStore.State] = []
        let cancellable = store.$state.sink { observedStates.append($0) }
        defer {
            cancellable.cancel()
            UpdateStreamURLProtocol.statusCode = 200
            UpdateStreamURLProtocol.body = Data()
            UpdateStreamURLProtocol.chunkSize = 0
            UpdateStreamURLProtocol.chunkInterval = 0
        }
        UpdateStreamURLProtocol.statusCode = 200
        UpdateStreamURLProtocol.body = Data(repeating: 0xAD, count: 64 * 1024)
        UpdateStreamURLProtocol.chunkSize = 8 * 1024
        UpdateStreamURLProtocol.chunkInterval = 0.05

        store.commitAutomaticUpdate(
            release: makeAvailableUpdate("99.9.9", provider: .github),
            notes: nil,
            expectedSourceRevision: store.updateSourceRevision
        )
        store.installLatest()
        XCTAssertEqual(store.state, .downloading)
        XCTAssertNil(store.downloadProgress)

        let sawProgress = await waitUntil { store.downloadProgress != nil }
        XCTAssertTrue(sawProgress, "The store must publish download progress")
        let failed = await waitUntil {
            if case .failed = store.state { return true }
            return false
        }
        XCTAssertTrue(failed, "The size mismatch must fail the install")
        XCTAssertNil(store.downloadProgress, "A failed install must clear progress")
        // The network transfer's end is a separate lifecycle event: the
        // store enters .installing for verification/mounting right when the
        // transfer completes, never lingering in .downloading at 100%.
        let installingIndex = observedStates.firstIndex(of: .installing)
        let failedIndex = observedStates.firstIndex { state in
            if case .failed = state { return true }
            return false
        }
        XCTAssertNotNil(installingIndex, "Transfer completion must move the store to .installing")
        XCTAssertNotNil(failedIndex)
        XCTAssertLessThan(installingIndex ?? .max, failedIndex ?? .min)
    }

    func testAutomaticInstallOpensAboutPageBeforeStartingInstall() async {
        var order: [String] = []
        let suite = "AutomaticUpdateOrder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let checker = StubUpdateChecker(
            result: .success(.available(makeRelease("99.9.9"), notes: nil))
        )
        let store = AppUpdateStore(checking: checker, defaults: defaults)
        let presenter = FakeUpdatePromptPresenter()
        let coordinator = AutomaticUpdateCheckCoordinator(
            checker: checker,
            store: store,
            presenter: presenter,
            environment: FakeUpdatePromptEnvironment(),
            networkStatus: FakeNetworkStatus(),
            defaults: defaults,
            startupDelay: .zero,
            install: { order.append("install") },
            showDetails: { order.append("details") }
        )
        defer { coordinator.stop() }

        coordinator.runAutomaticCheckIfNeeded()
        await coordinator.awaitCurrentCheck()
        presenter.dismiss(choosingInstall: true)

        // The About page must open before the install starts so the download
        // progress is visible there instead of running in the background.
        XCTAssertEqual(order, ["details", "install"])
    }

    // MARK: - Localization

    func testAutoUpdatePromptKeysExistInBothLanguagesAndFormatInEnglish() {
        let english = AppLocalizer.localizedValues(for: "en")
        let chinese = AppLocalizer.localizedValues(for: "zh-Hans")
        let keys = [
            "update.auto.window.title",
            "update.auto.prompt.title",
            "update.auto.prompt.versionTransition",
            "update.auto.prompt.highlights",
            "update.auto.prompt.safeInstall",
            "update.auto.prompt.install",
            "update.auto.prompt.later",
            "update.auto.prompt.details"
        ]
        for key in keys {
            XCTAssertNotNil(english[key], "Missing English key: \(key)")
            XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
        }
        XCTAssertEqual(
            String(format: tryUnwrap(english["update.auto.prompt.versionTransition"]), "2.7.0", "2.7.1"),
            "2.7.0 → 2.7.1"
        )
        XCTAssertEqual(english["update.auto.prompt.install"], "Update Now")
        XCTAssertEqual(english["update.auto.prompt.later"], "Later")
        XCTAssertEqual(english["update.auto.prompt.details"], "View Details")
    }

    func testDownloadProgressKeysExistInBothLanguagesAndFormatInEnglish() {
        let english = AppLocalizer.localizedValues(for: "en")
        let chinese = AppLocalizer.localizedValues(for: "zh-Hans")
        let keys = [
            "update.downloading.from",
            "update.downloading.bytes",
            "update.downloading.received"
        ]
        for key in keys {
            XCTAssertNotNil(english[key], "Missing English key: \(key)")
            XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
        }
        XCTAssertEqual(
            String(format: tryUnwrap(english["update.downloading.from"]), "GitHub"),
            "Downloading the update from GitHub"
        )
        XCTAssertEqual(
            String(format: tryUnwrap(english["update.downloading.bytes"]), "37.8 MB", "59.6 MB"),
            "Downloaded 37.8 MB of 59.6 MB"
        )
    }

    private func tryUnwrap(_ value: String?) -> String {
        guard let value else {
            XCTFail("Required localization value is missing")
            return ""
        }
        return value
    }
}



