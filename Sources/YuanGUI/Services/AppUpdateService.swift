import AppKit
// Used only for downloaded-asset SHA-256 verification; manifest signing is
// intentionally not part of this update flow.
import CryptoKit
import Foundation

enum AppVersionInfo {
    // Keep the source fallback aligned with the temporary manual-verification
    // build. Packaged builds still receive these values from Info.plist.
    static let fallbackVersion = "2.7.0"
    static let fallbackBuild = "16"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static var currentReleaseHighlights: [String] {
        [
            "release.2.7.1.musicArchitecture",
            "release.2.7.1.refreshBoundaries",
            "release.2.7.1.focusCompanion",
            "release.2.7.1.playerControls",
            "release.2.7.1.lyricBubble",
            "release.2.7.1.liquidGlass",
            "release.2.7.1.stability"
        ].map { AppLocalizer.string($0) }
    }
}

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
        case digest
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
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

    func releaseNotesAsset(for language: AppLanguage) -> GitHubReleaseAsset? {
        let effectiveLanguage = language == .system ? AppLocalizer.effectiveLanguage : language
        let preferredName = effectiveLanguage == .simplifiedChinese
            ? "RELEASE_NOTES.zh-CN.md"
            : "RELEASE_NOTES.md"
        return assets.first { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }
    }

    func asAvailableUpdate() -> AvailableUpdate {
        let assets = assets
            .filter { $0.name.lowercased().hasSuffix(".dmg") }
            .map { asset in
                UpdateAsset(
                    provider: .github,
                    downloadURL: asset.downloadURL,
                    sha256: asset.digest?.replacingOccurrences(of: "sha256:", with: ""),
                    size: Int64(asset.size)
                )
            }
        return AvailableUpdate(
            version: version,
            build: nil,
            minimumSystemVersion: nil,
            publishedAt: nil,
            localizedHighlights: UpdateHighlightExtractor.highlights(from: body),
            releasePageURL: pageURL,
            assets: assets,
            metadataSource: .githubReleaseAPI
        )
    }
}

enum SemanticVersion {
    static func isValid(_ value: String) -> Bool {
        let pattern = #"^[0-9]+\.[0-9]+(?:\.[0-9]+)*(?:[-+][0-9A-Za-z.-]+)?$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

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

/// A typed, non-throwing outcome of a completed update check. Network and
/// GitHub errors keep being expressed through `throws`.
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(AvailableUpdate)
    case available(AvailableUpdate, notes: String?)
}

/// The minimal capability an update checker must expose. `AppUpdateService`
/// conforms so the store and the automatic coordinator share one comparison path.
protocol UpdateChecking: Sendable {
    func checkForUpdate() async throws -> UpdateCheckResult
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case releaseUnavailable(String)
    case updateManifestUnavailable
    case invalidManifest(String)
    case checksumMismatch
    case checksumUnavailable
    case assetSizeMismatch
    case noCompatibleAsset
    case unsupportedSystemVersion
    case dmgMissing
    case invalidDownloadURL
    case mountFailed(String)
    case appMissing
    case invalidBundle
    case invalidVersion(String)
    case invalidBuild(String)
    case invalidSignature
    case installLocationNotWritable(String)
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return AppLocalizer.string("GitHub 返回了无法识别的响应。")
        case .releaseUnavailable(let message): return AppLocalizer.format("about.error.releaseUnavailable", message)
        case .updateManifestUnavailable: return AppLocalizer.string("update.error.manifestUnavailable")
        case .invalidManifest(let message): return AppLocalizer.format("update.error.invalidManifest", message)
        case .checksumMismatch: return AppLocalizer.string("update.error.checksumMismatch")
        case .checksumUnavailable: return AppLocalizer.string("update.error.checksumUnavailable")
        case .assetSizeMismatch: return AppLocalizer.string("update.error.assetSizeMismatch")
        case .noCompatibleAsset: return AppLocalizer.string("update.error.noCompatibleAsset")
        case .unsupportedSystemVersion: return AppLocalizer.string("update.error.unsupportedSystemVersion")
        case .dmgMissing: return AppLocalizer.string("这个 Release 没有可用的 DMG 文件。")
        case .invalidDownloadURL: return AppLocalizer.string("Release 下载地址不安全或无效。")
        case .mountFailed(let message): return AppLocalizer.format("about.error.mountFailed", message)
        case .appMissing: return AppLocalizer.string("更新镜像中没有 YuanGUI.app。")
        case .invalidBundle: return AppLocalizer.string("下载的应用标识与 YuanGUI 不一致。")
        case .invalidVersion(let version): return AppLocalizer.format("about.error.invalidVersion", version)
        case .invalidBuild(let build): return AppLocalizer.format("about.error.invalidBuild", build)
        case .invalidSignature: return AppLocalizer.string("下载的应用代码签名校验失败。")
        case .installLocationNotWritable(let path): return AppLocalizer.format("about.error.installLocation", path)
        case .helperFailed(let message): return AppLocalizer.format("about.error.helperFailed", message)
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

actor URLUpdateSourceFetcher: UpdateSourceFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchManifest(endpoint: UpdateEndpoint, timeout: TimeInterval) async throws -> AvailableUpdate {
        let jsonData = try await fetch(endpoint.manifestURL, timeout: timeout, accept: "application/json")
        let manifest = try UpdateManifestCodec.decodeAndValidate(jsonData: jsonData)
        return manifest.asAvailableUpdate(
            source: .manifest(endpoint.manifestURL),
            language: AppLocalizer.effectiveLanguage
        )
    }

    func fetchGitHubRelease(timeout: TimeInterval) async throws -> AvailableUpdate {
        let url = AppUpdateService.latestReleaseURL
        let data = try await fetch(url, timeout: timeout, accept: "application/vnd.github+json")
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return release.asAvailableUpdate()
    }

    private func fetch(_ url: URL, timeout: TimeInterval, accept: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("YuanGUI/\(AppVersionInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.releaseUnavailable("HTTP \(http.statusCode)")
        }
        return data
    }
}

actor AppUpdateService: UpdateChecking {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/YangChen-cn/yuangui/releases/latest")!
    private let session: URLSession
    private let fileManager: FileManager
    private let sourceFetcher: UpdateSourceFetching

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        sourceFetcher: UpdateSourceFetching? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.sourceFetcher = sourceFetcher ?? URLUpdateSourceFetcher(session: session)
    }

    func checkForUpdate() async throws -> UpdateCheckResult {
        let validManifests = await withTaskGroup(of: AvailableUpdate?.self, returning: [AvailableUpdate].self) { group in
            for endpoint in UpdateEndpoint.manifests {
                group.addTask { [sourceFetcher] in
                    try? await sourceFetcher.fetchManifest(
                        endpoint: endpoint,
                        timeout: endpoint.automaticTimeout
                    )
                }
            }
            var updates: [AvailableUpdate] = []
            for await update in group {
                if let update { updates.append(update) }
            }
            return updates
        }

        let candidate: AvailableUpdate
        if let selected = Self.selectBest(validManifests) {
            candidate = selected
        } else {
            do {
                candidate = try await sourceFetcher.fetchGitHubRelease(timeout: 8)
            } catch {
                throw AppUpdateError.updateManifestUnavailable
            }
        }

        guard SemanticVersion.isNewer(candidate.version, than: AppVersionInfo.version) else {
            return .upToDate(candidate)
        }
        let notes = candidate.localizedHighlights.isEmpty
            ? nil
            : candidate.localizedHighlights.map { "- \($0)" }.joined(separator: "\n")
        return .available(candidate, notes: notes)
    }

    static func selectBest(_ updates: [AvailableUpdate]) -> AvailableUpdate? {
        guard let highestVersion = updates.map(\.version).max(by: {
            SemanticVersion.compare($0, $1) == .orderedAscending
        }) else { return nil }
        let sameVersion = updates.filter {
            SemanticVersion.compare($0.version, highestVersion) == .orderedSame
        }
        guard let first = sameVersion.first else { return nil }
        var mergedAssets: [UpdateAsset] = []
        var identities = Set<String>()
        for update in sameVersion.sorted(by: { $0.assets.count > $1.assets.count }) {
            for asset in update.assets {
                let identity = "\(asset.provider.rawValue)|\(asset.downloadURL.absoluteString)"
                if identities.insert(identity).inserted { mergedAssets.append(asset) }
            }
        }
        let highlights = sameVersion.max(by: { $0.localizedHighlights.count < $1.localizedHighlights.count })?.localizedHighlights
            ?? first.localizedHighlights
        let preferredSource = sameVersion.first(where: { $0.metadataSource != .githubReleaseAPI })?.metadataSource
            ?? first.metadataSource
        return AvailableUpdate(
            version: first.version,
            build: sameVersion.compactMap(\.build).max(),
            minimumSystemVersion: sameVersion.compactMap(\.minimumSystemVersion).first,
            publishedAt: sameVersion.compactMap(\.publishedAt).max(),
            localizedHighlights: highlights,
            releasePageURL: sameVersion.compactMap(\.releasePageURL).first,
            assets: mergedAssets,
            metadataSource: preferredSource
        )
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

    func releaseNotes(for release: GitHubRelease, language: AppLanguage = AppLocalizer.effectiveLanguage) async throws -> String {
        guard let asset = release.releaseNotesAsset(for: language) else { return release.body }
        guard asset.downloadURL.scheme?.lowercased() == "https", asset.downloadURL.host == "github.com" else {
            throw AppUpdateError.invalidDownloadURL
        }

        var request = URLRequest(url: asset.downloadURL, timeoutInterval: 20)
        request.setValue("YuanGUI/\(AppVersionInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.invalidResponse
        }
        guard let notes = String(data: data, encoding: .utf8) else { throw AppUpdateError.invalidResponse }
        return notes
    }

    func prepare(_ update: AvailableUpdate) async throws -> PreparedAppUpdate {
        let orderedAssets = update.assets.sorted { lhs, rhs in
            Self.assetPriority(lhs.provider) < Self.assetPriority(rhs.provider)
        }
        guard !orderedAssets.isEmpty else { throw AppUpdateError.noCompatibleAsset }

        var lastError: Error = AppUpdateError.noCompatibleAsset
        for asset in orderedAssets {
            do {
                return try await prepare(asset: asset, for: update)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func discard(_ update: PreparedAppUpdate) {
        try? detach(update.mountPoint)
        try? fileManager.removeItem(at: update.dmgURL.deletingLastPathComponent())
    }

    private static func assetPriority(_ provider: UpdateAsset.Provider) -> Int {
        switch provider {
        case .gitee: 0
        case .github: 1
        case .other: 2
        }
    }

    private func prepare(asset: UpdateAsset, for update: AvailableUpdate) async throws -> PreparedAppUpdate {
        guard asset.downloadURL.scheme?.lowercased() == "https", asset.downloadURL.host != nil else {
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
        let fileName = asset.downloadURL.lastPathComponent.isEmpty ? "YuanGUI-update.dmg" : asset.downloadURL.lastPathComponent
        let dmgURL = updateDirectory.appendingPathComponent(fileName)

        do {
            try fileManager.moveItem(at: temporaryURL, to: dmgURL)
            try verifyDownloadedAsset(at: dmgURL, asset: asset)
            let mountPoint = try mount(dmgURL)
            do {
                return try validateMountedUpdate(
                    mountPoint: mountPoint,
                    dmgURL: dmgURL,
                    update: update
                )
            } catch {
                try? detach(mountPoint)
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: updateDirectory)
            throw error
        }
    }

    private func verifyDownloadedAsset(at url: URL, asset: UpdateAsset) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        if let expectedSize = asset.size, actualSize != expectedSize {
            throw AppUpdateError.assetSizeMismatch
        }
        guard let expectedHash = asset.sha256 else { throw AppUpdateError.checksumUnavailable }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else { throw AppUpdateError.checksumMismatch }
    }

    private func validateMountedUpdate(
        mountPoint: URL,
        dmgURL: URL,
        update: AvailableUpdate
    ) throws -> PreparedAppUpdate {
        if let minimumSystemVersion = update.minimumSystemVersion,
           SemanticVersion.compare(currentSystemVersion(), minimumSystemVersion) == .orderedAscending {
            throw AppUpdateError.unsupportedSystemVersion
        }

        return try validateMountedUpdateWithoutSystemRequirement(
            mountPoint: mountPoint,
            dmgURL: dmgURL,
            update: update
        )
    }

    private func validateMountedUpdateWithoutSystemRequirement(
        mountPoint: URL,
        dmgURL: URL,
        update: AvailableUpdate
    ) throws -> PreparedAppUpdate {
        let sourceApp = mountPoint.appendingPathComponent("YuanGUI.app", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceApp.path) else { throw AppUpdateError.appMissing }
        guard let bundle = Bundle(url: sourceApp), bundle.bundleIdentifier == "com.yang.yuangui" else {
            throw AppUpdateError.invalidBundle
        }
        let bundledVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard SemanticVersion.compare(bundledVersion, update.version) == .orderedSame else {
            throw AppUpdateError.invalidVersion(bundledVersion)
        }
        if let expectedBuild = update.build {
            let bundledBuild = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            guard bundledBuild == expectedBuild else { throw AppUpdateError.invalidBuild(bundledBuild.map(String.init) ?? "unknown") }
        }
        guard verifySignature(sourceApp) else { throw AppUpdateError.invalidSignature }

        let targetApp = installationTarget()
        guard fileManager.isWritableFile(atPath: targetApp.deletingLastPathComponent().path) else {
            throw AppUpdateError.installLocationNotWritable(targetApp.path)
        }
        return PreparedAppUpdate(sourceApp: sourceApp, targetApp: targetApp, mountPoint: mountPoint, dmgURL: dmgURL)
    }

    private func currentSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
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
            throw AppUpdateError.mountFailed(String(data: result.error, encoding: .utf8) ?? AppLocalizer.string("未知错误"))
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
    @Published private(set) var latestUpdate: AvailableUpdate?
    @Published private(set) var latestUpdateNotes: String?
    private let service: AppUpdateService
    private let checking: UpdateChecking
    private var terminateForUpdate: @MainActor () async -> Bool = { false }

    /// Test seam: replaces the DMG download/install pipeline. When set,
    /// `installLatest()` runs this closure instead of touching the network,
    /// so tests can observe install attempts without real downloads.
    var installLauncher: ((AvailableUpdate) async throws -> Void)?

    init(service: AppUpdateService = AppUpdateService(), checking: UpdateChecking? = nil) {
        self.service = service
        self.checking = checking ?? service
    }

    var isBusy: Bool { state == .checking || state == .downloading || state == .installing }

    func setTerminationHandler(_ handler: @escaping @MainActor () async -> Bool) {
        terminateForUpdate = handler
    }

    func check() {
        guard !isBusy else { return }
        state = .checking
        latestUpdateNotes = nil
        Task {
            do {
                let result = try await checking.checkForUpdate()
                switch result {
                case .available(let update, let notes):
                    latestUpdate = update
                    latestUpdateNotes = notes
                    state = .available
                case .upToDate(let update):
                    latestUpdate = update
                    latestUpdateNotes = update.localizedHighlights.map { "- \($0)" }.joined(separator: "\n")
                    state = .upToDate
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Publishes an update discovered by the automatic coordinator without
    /// moving the store through `.checking` or surfacing an error. Returns
    /// false when a manual check or install is already in flight, so the
    /// coordinator stays quiet instead of fighting the other operation.
    @discardableResult
    func commitAutomaticUpdate(release: AvailableUpdate, notes: String?) -> Bool {
        guard !isBusy else { return false }
        latestUpdate = release
        latestUpdateNotes = notes
        state = .available
        return true
    }

    func installLatest() {
        guard let release = latestUpdate, SemanticVersion.isNewer(release.version, than: AppVersionInfo.version) else { return }
        guard !isBusy else { return }
        state = .downloading
        Task {
            do {
                if let installLauncher {
                    try await installLauncher(release)
                    state = .installing
                    return
                }
                let prepared = try await service.prepare(release)
                state = .installing
                guard await terminateForUpdate() else {
                    await service.discard(prepared)
                    state = .failed(AppLocalizer.string("日记保存失败，更新安装已取消。"))
                    return
                }
                do {
                    try launchInstaller(for: prepared)
                } catch {
                    await service.discard(prepared)
                    throw error
                }
                NSApp.terminate(nil)
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
