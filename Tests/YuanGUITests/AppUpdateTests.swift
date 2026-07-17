import Foundation
import XCTest
@testable import YuanGUI

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(SemanticVersion.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(SemanticVersion.isNewer("v1.1", than: "1.0.99"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.2", than: "1.0.2"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.1", than: "1.0.2"))
        XCTAssertEqual(SemanticVersion.compare("1.0", "1.0.0"), .orderedSame)
    }

    func testGitHubReleaseDecodesNotesAndFindsDMG() throws {
        let data = Data(#"{"tag_name":"v1.0.2","name":"元圭与 VCC 1.0.2","body":"更新日志","html_url":"https://github.com/YangChen-cn/yuangui/releases/tag/v1.0.2","assets":[{"name":"YuanGUI-1.0.2.dmg","browser_download_url":"https://github.com/YangChen-cn/yuangui/releases/download/v1.0.2/YuanGUI-1.0.2.dmg","size":1234}]}"#.utf8)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        XCTAssertEqual(release.version, "1.0.2")
        XCTAssertEqual(release.body, "更新日志")
        XCTAssertEqual(release.dmgAsset?.name, "YuanGUI-1.0.2.dmg")
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
