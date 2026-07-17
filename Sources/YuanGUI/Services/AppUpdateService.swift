import AppKit
import Foundation

enum AppVersionInfo {
    static let fallbackVersion = "1.0.4"
    static let fallbackBuild = "6"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static let currentReleaseHighlights = [
        "修复 Bilibili 接口偶发返回其他视频字幕轨的问题，AI 字幕按 aid/cid 校验，人工字幕使用轨道一致性确认。",
        "Apple Music 的 LRCLIB 歌词改用稳定缓存键，重启后可继续使用已匹配歌词。",
        "Bilibili 登录信息完整显示昵称和 UID，并支持仅修改歌曲名或歌手而不重新匹配歌词。",
        "歌词偏移新增手动输入与 0.1 秒微调，状态栏、完整播放器和歌词设置操作保持一致。",
        "提高桌宠聊天气泡的不透明度及深色模式对比度，深色桌面上更易阅读。"
    ]
}

struct GitHubReleaseAsset: Decodable, Equatable {
    let name: String
    let downloadURL: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let name: String?
    let body: String
    let pageURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case pageURL = "html_url"
        case assets
    }

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var dmgAsset: GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

enum SemanticVersion {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ value: String) -> [Int] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case releaseUnavailable(String)
    case dmgMissing
    case invalidDownloadURL
    case mountFailed(String)
    case appMissing
    case invalidBundle
    case invalidVersion(String)
    case invalidSignature
    case installLocationNotWritable(String)
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub 返回了无法识别的响应。"
        case .releaseUnavailable(let message): return "读取 Release 失败：\(message)"
        case .dmgMissing: return "这个 Release 没有可用的 DMG 文件。"
        case .invalidDownloadURL: return "Release 下载地址不安全或无效。"
        case .mountFailed(let message): return "无法打开更新镜像：\(message)"
        case .appMissing: return "更新镜像中没有 YuanGUI.app。"
        case .invalidBundle: return "下载的应用标识与 YuanGUI 不一致。"
        case .invalidVersion(let version): return "下载的应用版本（\(version)）与 Release 不一致。"
        case .invalidSignature: return "下载的应用代码签名校验失败。"
        case .installLocationNotWritable(let path): return "没有权限更新 \(path)，请先把应用移到可写位置或“应用程序”文件夹。"
        case .helperFailed(let message): return "无法启动更新安装器：\(message)"
        }
    }
}

struct PreparedAppUpdate {
    let sourceApp: URL
    let targetApp: URL
    let mountPoint: URL
    let dmgURL: URL
}

enum AppUpdateInstallerScript {
    static let source = """
    #!/bin/zsh
    set -eu
    source_app="$1"
    target_app="$2"
    mount_point="$3"
    dmg_path="$4"
    old_pid="$5"
    staging="${target_app}.updating-${old_pid}"
    backup="${target_app}.backup-${old_pid}"
    wait_attempts=0
    while /bin/kill -0 "$old_pid" 2>/dev/null; do
      if (( wait_attempts >= 50 )); then
        print -u2 "YuanGUI did not quit after 10 seconds; sending TERM"
        /bin/kill -TERM "$old_pid" 2>/dev/null || true
        break
      fi
      /bin/sleep 0.2
      (( wait_attempts += 1 ))
    done
    force_attempts=0
    while /bin/kill -0 "$old_pid" 2>/dev/null; do
      if (( force_attempts >= 25 )); then
        print -u2 "YuanGUI ignored TERM for 5 seconds; sending KILL"
        /bin/kill -KILL "$old_pid" 2>/dev/null || true
        break
      fi
      /bin/sleep 0.2
      (( force_attempts += 1 ))
    done
    /usr/bin/ditto "$source_app" "$staging"
    if [[ -e "$target_app" ]]; then /bin/mv "$target_app" "$backup"; fi
    if /bin/mv "$staging" "$target_app"; then
      /bin/rm -rf "$backup"
      /usr/bin/open -n "$target_app"
    else
      [[ -e "$backup" ]] && /bin/mv "$backup" "$target_app"
      exit 1
    fi
    /usr/bin/hdiutil detach "$mount_point" -quiet || true
    /bin/rm -rf "${dmg_path:h}"
    /bin/rm -f "$0"
    """
}

actor AppUpdateService {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/YangChen-cn/yuangui/releases/latest")!
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("YuanGUI/\(AppVersionInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.releaseUnavailable("HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func prepare(_ release: GitHubRelease) async throws -> PreparedAppUpdate {
        guard let asset = release.dmgAsset else { throw AppUpdateError.dmgMissing }
        guard asset.downloadURL.scheme == "https", asset.downloadURL.host == "github.com" else {
            throw AppUpdateError.invalidDownloadURL
        }

        var request = URLRequest(url: asset.downloadURL, timeoutInterval: 120)
        request.setValue("YuanGUI/\(AppVersionInfo.version)", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.invalidResponse
        }

        let updateDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("YuanGUI-Update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        let dmgURL = updateDirectory.appendingPathComponent(asset.name)
        try fileManager.moveItem(at: temporaryURL, to: dmgURL)

        let mountPoint = try mount(dmgURL)
        let sourceApp = mountPoint.appendingPathComponent("YuanGUI.app", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceApp.path) else {
            try? detach(mountPoint)
            throw AppUpdateError.appMissing
        }

        guard let bundle = Bundle(url: sourceApp),
              bundle.bundleIdentifier == "com.yang.yuangui" else {
            try? detach(mountPoint)
            throw AppUpdateError.invalidBundle
        }
        let bundledVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard SemanticVersion.compare(bundledVersion, release.version) == .orderedSame else {
            try? detach(mountPoint)
            throw AppUpdateError.invalidVersion(bundledVersion)
        }
        guard verifySignature(sourceApp) else {
            try? detach(mountPoint)
            throw AppUpdateError.invalidSignature
        }

        let targetApp = installationTarget()
        guard fileManager.isWritableFile(atPath: targetApp.deletingLastPathComponent().path) else {
            try? detach(mountPoint)
            throw AppUpdateError.installLocationNotWritable(targetApp.path)
        }
        return PreparedAppUpdate(sourceApp: sourceApp, targetApp: targetApp, mountPoint: mountPoint, dmgURL: dmgURL)
    }

    private func installationTarget() -> URL {
        let current = Bundle.main.bundleURL
        if current.pathExtension.lowercased() == "app" { return current }
        return URL(fileURLWithPath: "/Applications/YuanGUI.app", isDirectory: true)
    }

    private func mount(_ dmgURL: URL) throws -> URL {
        let result = run("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"])
        guard result.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: result.output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw AppUpdateError.mountFailed(String(data: result.error, encoding: .utf8) ?? "未知错误")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func detach(_ mountPoint: URL) throws {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    private func verifySignature(_ appURL: URL) -> Bool {
        run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path]).status == 0
    }

    private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        do { try process.run() } catch { return (-1, Data(), Data(error.localizedDescription.utf8)) }
        process.waitUntilExit()
        return (process.terminationStatus, output.fileHandleForReading.readDataToEndOfFile(), error.fileHandleForReading.readDataToEndOfFile())
    }
}

@MainActor
final class AppUpdateStore: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, available, downloading, installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestRelease: GitHubRelease?
    private let service: AppUpdateService

    init(service: AppUpdateService = AppUpdateService()) {
        self.service = service
    }

    var isBusy: Bool { state == .checking || state == .downloading || state == .installing }

    func check() {
        guard !isBusy else { return }
        state = .checking
        Task {
            do {
                let release = try await service.latestRelease()
                latestRelease = release
                state = SemanticVersion.isNewer(release.version, than: AppVersionInfo.version) ? .available : .upToDate
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func installLatest() {
        guard let release = latestRelease, SemanticVersion.isNewer(release.version, than: AppVersionInfo.version) else { return }
        state = .downloading
        Task {
            do {
                let prepared = try await service.prepare(release)
                state = .installing
                try launchInstaller(for: prepared)
                NotificationCenter.default.post(name: .terminateYuanGUIForUpdate, object: nil)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func launchInstaller(for update: PreparedAppUpdate) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuangui-update-\(UUID().uuidString).zsh")
        try Data(AppUpdateInstallerScript.source.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path, update.sourceApp.path, update.targetApp.path, update.mountPoint.path, update.dmgURL.path, "\(ProcessInfo.processInfo.processIdentifier)"]
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("yuangui-update.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        process.standardOutput = log
        process.standardError = log
        do { try process.run() }
        catch { throw AppUpdateError.helperFailed(error.localizedDescription) }
    }
}
