import CryptoKit
import Foundation
import XCTest
@testable import YuanGUI

private enum UpdateSourceStubError: Error, Sendable {
    case unavailable
}

private actor FakeUpdateSourceFetcher: UpdateSourceFetching {
    enum ResultValue: Sendable {
        case update(AvailableUpdate)
        case unavailable
    }

    private let manifestResults: [UpdateAsset.Provider: ResultValue]
    private let apiResult: ResultValue
    private(set) var manifestCallCount = 0
    private(set) var apiCallCount = 0

    init(
        gitee: ResultValue = .unavailable,
        github: ResultValue = .unavailable,
        api: ResultValue = .unavailable
    ) {
        manifestResults = [.gitee: gitee, .github: github]
        apiResult = api
    }

    func fetchManifest(endpoint: UpdateEndpoint, timeout: TimeInterval) async throws -> AvailableUpdate {
        manifestCallCount += 1
        guard case .update(let update) = manifestResults[endpoint.provider] else {
            throw UpdateSourceStubError.unavailable
        }
        return update
    }

    func fetchGitHubRelease(timeout: TimeInterval) async throws -> AvailableUpdate {
        apiCallCount += 1
        guard case .update(let update) = apiResult else {
            throw UpdateSourceStubError.unavailable
        }
        return update
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
        metadataSource: .manifest(URL(string: "https://updates.example.com/\(provider.rawValue)/latest.json")!)
    )
}

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(SemanticVersion.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(SemanticVersion.isNewer("v1.1", than: "1.0.99"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.2", than: "1.0.2"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.1", than: "1.0.2"))
        XCTAssertEqual(SemanticVersion.compare("1.0", "1.0.0"), .orderedSame)
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
        let fetcher = FakeUpdateSourceFetcher(gitee: .update(gitee))
        let service = AppUpdateService(sourceFetcher: fetcher)

        let result = try await service.checkForUpdate()
        guard case .available(let update, _) = result else {
            return XCTFail("A newer Gitee manifest should be available")
        }
        XCTAssertEqual(update.version, "99.9.9")
        XCTAssertEqual(update.metadataSource, gitee.metadataSource)
        let apiCalls = await fetcher.apiCallCount
        XCTAssertEqual(apiCalls, 0)
    }

    func testDualSourceSelectsTheHighestVersionAndMergesSameVersionAssets() {
        let older = makeAvailableUpdate("2.7.2", provider: .gitee)
        let newer = makeAvailableUpdate("2.7.3", provider: .github)
        let giteeSame = makeAvailableUpdate("2.7.4", provider: .gitee, assetCount: 1)
        let githubSame = makeAvailableUpdate("2.7.4", provider: .github, assetCount: 1)

        let highest = AppUpdateService.selectBest([older, newer])
        XCTAssertEqual(highest?.version, "2.7.3")
        XCTAssertEqual(highest?.metadataSource, newer.metadataSource)

        let merged = AppUpdateService.selectBest([giteeSame, githubSame])
        XCTAssertEqual(merged?.version, "2.7.4")
        XCTAssertEqual(merged?.assets.count, 2)
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

    func testAllUpdateSourcesFailWithoutSurfacingAFalseUpdate() async {
        let fetcher = FakeUpdateSourceFetcher()
        let service = AppUpdateService(sourceFetcher: fetcher)

        do {
            _ = try await service.checkForUpdate()
            XCTFail("All update sources should fail")
        } catch AppUpdateError.updateManifestUnavailable {
            let apiCalls = await fetcher.apiCallCount
            XCTAssertEqual(apiCalls, 1)
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
