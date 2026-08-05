import AppKit
// Used only for downloaded-asset SHA-256 verification; manifest signing is
// intentionally not part of this update flow.
import CryptoKit
import Foundation

enum AppVersionInfo {
    // Packaged builds receive these values from Info.plist; the fallback is
    // only used when the running bundle is missing its version keys.
    static let fallbackVersion = "2.8.0"
    static let fallbackBuild = "19"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static var currentReleaseHighlights: [String] {
        [
            "release.2.8.0.translationSpeech",
            "release.2.8.0.musicWindows",
            "release.2.8.0.finderExtension",
            "release.2.8.0.petOnboarding",
            "release.2.8.0.petToolsMenu",
            "release.2.8.0.featureTips",
            "release.2.8.0.temporaryUnlock",
            "release.2.8.0.captureContract",
            "release.2.8.0.slowSwitch",
            "release.2.8.0.sourcePreference"
        ].map { AppLocalizer.string($0) }
    }

    /// The single update decision shared by the check and install paths:
    /// a higher version wins; an equal version is still an update when the
    /// remote build is higher (repair releases reuse the semantic version).
    /// A candidate without a build number (GitHub API fallback) never counts
    /// as newer on equal versions, and an unparseable local build never lets
    /// the remote win.
    static func isNewer(
        _ candidate: AvailableUpdate,
        thanCurrentVersion currentVersion: String = version,
        currentBuild: String = build
    ) -> Bool {
        switch SemanticVersion.compare(candidate.version, currentVersion) {
        case .orderedDescending:
            return true
        case .orderedAscending:
            return false
        case .orderedSame:
            guard let candidateBuild = candidate.build,
                  let localBuild = Int(currentBuild) else { return false }
            return candidateBuild > localBuild
        }
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
    let isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case pageURL = "html_url"
        case assets
        case isPrerelease = "prerelease"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
        isPrerelease = try container.decodeIfPresent(Bool.self, forKey: .isPrerelease) ?? false
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

    func asAvailableUpdate(localizedHighlights: [String]? = nil) -> AvailableUpdate {
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
            localizedHighlights: localizedHighlights ?? UpdateHighlightExtractor.highlights(from: body),
            releasePageURL: pageURL,
            assets: assets,
            metadataSource: .githubReleaseAPI
        )
    }
}

enum SemanticVersion {
    static func isValid(_ value: String) -> Bool {
        isStable(value)
    }

    static func isStable(_ value: String) -> Bool {
        let pattern = #"^[0-9]+\.[0-9]+(?:\.[0-9]+)*$"#
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
enum UpdateCheckMode: Sendable, Equatable {
    case automatic
    case manual
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(AvailableUpdate)
    case available(AvailableUpdate, notes: String?)
}

private enum ManifestFetchOutcome: Sendable {
    case succeeded(AvailableUpdate)
    case availability(UpdateSourceAvailabilityError)
    case invalid(AppUpdateError)
}

private enum ManifestHedgeEvent: Sendable {
    case github(ManifestFetchOutcome)
    case gitee(ManifestFetchOutcome)
    case startGitee
    case githubDeadline
    case backupDeadline
}

private enum ManifestHedgeDecision: Sendable {
    case update(AvailableUpdate)
    case apiFallback
    case failure(AppUpdateError)
}

// Internal for testability: unit tests drive the sliding-window rate logic
// with an injected fake clock.
actor DownloadProgressTracker {
    private var lastProgress: Date
    private var totalBytes: Int64 = 0
    /// Sliding-window (date, cumulative bytes) samples for rate measurement.
    private var samples: [(date: Date, bytes: Int64)] = []
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.lastProgress = now()
        self.now = now
    }

    func markProgress(bytes: Int64) {
        let timestamp = now()
        lastProgress = timestamp
        totalBytes = bytes
        samples.append((timestamp, bytes))
        // Keep only a bounded history; a couple of minutes of 2s samples is
        // far more than the observation window ever needs.
        if samples.count > 128 {
            samples.removeFirst(samples.count - 128)
        }
    }

    func totalBytesRead() -> Int64 {
        totalBytes
    }

    func isStale(after interval: TimeInterval) -> Bool {
        now().timeIntervalSince(lastProgress) >= interval
    }

    /// Sustained-slow detection with a true trailing window: the baseline is
    /// the newest sample at or before `now - window`, so the rate always
    /// covers roughly the trailing `window` instead of the whole transfer
    /// history. A long transfer at a constant slow rate stays slow forever
    /// instead of looking faster as history accumulates. History older than
    /// the baseline is pruned here (the monitor calls this every sample
    /// interval); the bounded cap in `markProgress` remains a backstop.
    func isSlow(under thresholdBytesPerSecond: Int64, window: TimeInterval) -> Bool {
        let timestamp = now()
        let cutoff = timestamp.addingTimeInterval(-window)
        guard samples.last != nil else { return false }
        if let baselineIndex = samples.lastIndex(where: { $0.date <= cutoff }) {
            samples.removeFirst(baselineIndex)
        } else {
            samples.removeAll { $0.date < cutoff }
        }
        guard let baseline = samples.first,
              let newest = samples.last else {
            return false
        }
        let elapsed = timestamp.timeIntervalSince(baseline.date)
        guard elapsed >= window else { return false }
        let windowBytes = newest.bytes - baseline.bytes
        return Double(windowBytes) / elapsed < Double(thresholdBytesPerSecond)
    }
}

/// The minimal capability an update checker must expose. `AppUpdateService`
/// conforms so the store and the automatic coordinator share one comparison path.
protocol UpdateChecking: Sendable {
    func checkForUpdate() async throws -> UpdateCheckResult

    /// Manual checks retain their original, user-facing behavior while the
    /// automatic coordinator can use shorter, quiet source checks.
    func checkForUpdate(mode: UpdateCheckMode) async throws -> UpdateCheckResult
}

extension UpdateChecking {
    func checkForUpdate(mode: UpdateCheckMode) async throws -> UpdateCheckResult {
        try await checkForUpdate()
    }
}

enum AppUpdateError: LocalizedError, Sendable {
    case invalidResponse
    case releaseUnavailable(String)
    case updateManifestUnavailable
    case updateSourcesUnavailable
    case prereleaseNotSupported
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
        case .updateSourcesUnavailable: return AppLocalizer.string("update.error.sourcesUnavailable")
        case .prereleaseNotSupported: return AppLocalizer.string("update.error.manifestUnavailable")
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

/// Only transport failures in this set may trigger a source fallback. Package
/// validation, local file errors, and HTTP configuration errors deliberately
/// remain outside this type so they stop the update immediately.
enum UpdateSourceAvailabilityError: Error, Equatable, Sendable {
    case timedOut
    case cannotFindHost
    case cannotConnectToHost
    case dnsLookupFailed
    case networkConnectionLost
    case notConnectedToInternet
    case resourceUnavailable
    /// The transfer started but its sustained rate stayed below the policy
    /// threshold for the observation window (slow, not stalled). Treated as a
    /// transport failure so the existing GitHub → Gitee fallback applies.
    case downloadTooSlow
    case httpStatus(Int)

    init?(urlError: URLError) {
        switch urlError.code {
        case .timedOut: self = .timedOut
        case .cannotFindHost: self = .cannotFindHost
        case .cannotConnectToHost: self = .cannotConnectToHost
        case .dnsLookupFailed: self = .dnsLookupFailed
        case .networkConnectionLost: self = .networkConnectionLost
        case .notConnectedToInternet: self = .notConnectedToInternet
        case .resourceUnavailable: self = .resourceUnavailable
        default: return nil
        }
    }

    static func isFallbackHTTPStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }
}

/// A snapshot of the DMG transfer, published to the UI. The provider is part
/// of the model because an automatic GitHub → Gitee switch restarts the byte
/// count from zero; the UI must show the new source and its own percentage
/// instead of a misleading stale one. `totalBytes` is nil when the size is
/// unknown (indeterminate progress).
struct UpdateDownloadProgress: Equatable, Sendable {
    let provider: UpdateAsset.Provider
    let receivedBytes: Int64
    let totalBytes: Int64?

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
    }
}

/// A transfer lifecycle event emitted by the service: throttled progress
/// snapshots, then a final `downloadCompleted` when the network transfer ends.
/// Everything after the transfer (SHA-256, mounting, validation, signing)
/// belongs to the store's `.installing` phase, not to the download.
enum UpdateDownloadEvent: Equatable, Sendable {
    case progress(UpdateDownloadProgress)
    case downloadCompleted
}

/// Receives transfer lifecycle events from the service. The service invokes
/// the handler on a dedicated drain task that is flushed when a transfer
/// attempt ends — the download writer itself only yields snapshots into a
/// buffer, so a slow UI can never stall the transfer or slow it enough to
/// trip the sustained-slow GitHub → Gitee monitor.
typealias UpdateDownloadEventHandler = @Sendable (UpdateDownloadEvent) async -> Void

struct PreparedAppUpdate: Sendable {
    let sourceApp: URL
    let targetApp: URL
    let mountPoint: URL
    let dmgURL: URL
}

/// Streams the DMG through CryptoKit so large update files are not copied into
/// one in-memory Data value. This is an asset checksum, not a manifest
/// signature; manifest trust still relies on HTTPS and the app-bundle checks.
func sha256(of fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
    finder_extension="${target_app}/Contents/PlugIns/YuanGUIFinderExtension.appex"
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
    /usr/bin/pkill -x "YuanGUIFinderExtension" 2>/dev/null || true
    /usr/bin/ditto "$source_app" "$staging"
    if [[ -e "$target_app" ]]; then /bin/mv "$target_app" "$backup"; fi
    if /bin/mv "$staging" "$target_app"; then
      if [[ -d "$finder_extension" ]]; then
        /usr/bin/pluginkit -a "$finder_extension" || true
      fi
      /usr/bin/pkill -x "YuanGUIFinderExtension" 2>/dev/null || true
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
    private let languageProvider: @Sendable () -> AppLanguage

    init(
        session: URLSession = .shared,
        languageProvider: @escaping @Sendable () -> AppLanguage = { AppLocalizer.effectiveLanguage }
    ) {
        self.session = session
        self.languageProvider = languageProvider
    }

    func fetchManifest(endpoint: UpdateEndpoint, timeout: TimeInterval) async throws -> AvailableUpdate {
        let jsonData = try await fetch(endpoint.manifestURL, timeout: timeout, accept: "application/json")
        let manifest = try UpdateManifestCodec.decodeAndValidate(jsonData: jsonData)
        return manifest.asAvailableUpdate(
            source: .manifest(endpoint.manifestURL, provider: endpoint.provider),
            language: languageProvider()
        )
    }

    func fetchGitHubRelease(timeout: TimeInterval) async throws -> AvailableUpdate {
        let url = AppUpdateService.latestReleaseURL
        let data = try await fetch(url, timeout: timeout, accept: "application/vnd.github+json")
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.isPrerelease, SemanticVersion.isStable(release.version) else {
            throw AppUpdateError.prereleaseNotSupported
        }
        return release.asAvailableUpdate()
    }

    func fetchGitHubRelease(timeout: TimeInterval, language: AppLanguage) async throws -> AvailableUpdate {
        let url = AppUpdateService.latestReleaseURL
        let data = try await fetch(url, timeout: timeout, accept: "application/vnd.github+json")
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.isPrerelease, SemanticVersion.isStable(release.version) else {
            throw AppUpdateError.prereleaseNotSupported
        }
        let notes: String
        if let notesAsset = release.releaseNotesAsset(for: language),
           notesAsset.downloadURL.scheme?.lowercased() == "https",
           notesAsset.downloadURL.host == "github.com",
           let notesData = try? await fetch(notesAsset.downloadURL, timeout: timeout, accept: "text/markdown"),
           let localizedNotes = String(data: notesData, encoding: .utf8) {
            notes = localizedNotes
        } else {
            notes = release.body
        }
        return release.asAvailableUpdate(
            localizedHighlights: UpdateHighlightExtractor.highlights(from: notes)
        )
    }

    private func fetch(_ url: URL, timeout: TimeInterval, accept: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("YuanGUI/\(AppVersionInfo.version)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw UpdateSourceAvailabilityError(urlError: error)
                ?? error
        }
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if UpdateSourceAvailabilityError.isFallbackHTTPStatus(http.statusCode) {
                throw UpdateSourceAvailabilityError.httpStatus(http.statusCode)
            }
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
    private let assetPreparer: (@Sendable (UpdateAsset, AvailableUpdate) async throws -> PreparedAppUpdate)?
    private let manifestHedge: UpdateManifestHedgeConfiguration
    private let downloadSourcePolicy: DownloadSourcePolicy
    private let updateSourcePreference: @Sendable () -> UpdateSourcePreference
    private let languageProvider: @Sendable () -> AppLanguage
    private var githubUnavailableUntil: Date? = nil
    /// Separate from `githubUnavailableUntil`: that one is cleared whenever a
    /// GitHub *manifest* succeeds (small files usually do), which would erase a
    /// slow-DMG decision immediately. This one remembers "GitHub downloads are
    /// too slow here" for the same 30-minute window and makes the next check
    /// prefer the Gitee asset without re-measuring.
    private var githubDownloadUnavailableUntil: Date? = nil

    private static let githubUnavailableCacheDuration: TimeInterval = 30 * 60

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        sourceFetcher: UpdateSourceFetching? = nil,
        assetPreparer: (@Sendable (UpdateAsset, AvailableUpdate) async throws -> PreparedAppUpdate)? = nil,
        manifestHedge: UpdateManifestHedgeConfiguration = .production,
        downloadSourcePolicy: DownloadSourcePolicy = .production,
        updateSourcePreference: @escaping @Sendable () -> UpdateSourcePreference = { .automatic },
        languageProvider: @escaping @Sendable () -> AppLanguage = { AppLocalizer.effectiveLanguage }
    ) {
        self.session = session
        self.fileManager = fileManager
        self.sourceFetcher = sourceFetcher ?? URLUpdateSourceFetcher(
            session: session,
            languageProvider: languageProvider
        )
        self.assetPreparer = assetPreparer
        self.manifestHedge = manifestHedge
        self.downloadSourcePolicy = downloadSourcePolicy
        self.updateSourcePreference = updateSourcePreference
        self.languageProvider = languageProvider
    }

    func checkForUpdate() async throws -> UpdateCheckResult {
        try await checkForUpdate(mode: .automatic)
    }

    func checkForUpdate(mode: UpdateCheckMode) async throws -> UpdateCheckResult {
        let candidate: AvailableUpdate
        switch await fetchManifestWithHedgedFallback(mode: mode) {
        case .update(let update):
            updateGitHubAvailabilityCache(for: update)
            candidate = update
        case .failure(let error):
            if case .updateManifestUnavailable = error {
                githubUnavailableUntil = Date().addingTimeInterval(Self.githubUnavailableCacheDuration)
            }
            throw error
        case .apiFallback:
            githubUnavailableUntil = Date().addingTimeInterval(Self.githubUnavailableCacheDuration)
            do {
                candidate = try await sourceFetcher.fetchGitHubRelease(
                    timeout: mode == .manual ? 20 : 8,
                    language: languageProvider()
                )
                AutomaticUpdateLog.log("update.source.github.api.succeeded")
            } catch AppUpdateError.unsupportedSystemVersion {
                throw AppUpdateError.unsupportedSystemVersion
            } catch AppUpdateError.prereleaseNotSupported {
                throw AppUpdateError.prereleaseNotSupported
            } catch {
                throw AppUpdateError.updateManifestUnavailable
            }
        }

        guard SemanticVersion.isStable(candidate.version) else {
            throw AppUpdateError.prereleaseNotSupported
        }
        guard AppVersionInfo.isNewer(candidate) else {
            return .upToDate(candidate)
        }
        let notes: String?
        if mode == .manual, candidate.metadataSource == .githubReleaseAPI {
            // The manifest carries concise automatic highlights. A manual
            // check can enrich the GitHub API fallback with the complete
            // localized notes. Manifest results are returned immediately;
            // AppUpdateStore may enrich them in the background so a Gitee
            // success never waits on an unreachable GitHub API.
            notes = (try? await fullReleaseNotes(for: candidate))
                ?? candidate.localizedHighlights.map { "- \($0)" }.joined(separator: "\n")
        } else {
            notes = candidate.localizedHighlights.isEmpty
                ? nil
                : candidate.localizedHighlights.map { "- \($0)" }.joined(separator: "\n")
        }
        return .available(candidate, notes: notes)
    }

    private func fetchManifestWithHedgedFallback(mode: UpdateCheckMode) async -> ManifestHedgeDecision {
        let githubTimeout = mode == .manual ? 20 : UpdateEndpoint.githubManifest.automaticTimeout
        let giteeTimeout = mode == .manual ? 20 : UpdateEndpoint.giteeManifest.automaticTimeout
        switch updateSourcePreference() {
        case .github:
            return await fetchSingleSource(endpoint: .githubManifest, timeout: githubTimeout)
        case .gitee:
            return await fetchSingleSource(endpoint: .giteeManifest, timeout: giteeTimeout)
        case .automatic:
            break
        }
        let sourceFetcher = self.sourceFetcher
        let hedge = self.manifestHedge
        let backupDeadline = mode == .manual
            ? hedge.manualBackupDeadline
            : hedge.automaticBackupDeadline

        return await withTaskGroup(of: ManifestHedgeEvent.self, returning: ManifestHedgeDecision.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                .github(await Self.fetchManifestOutcome(
                    sourceFetcher: sourceFetcher,
                    endpoint: .githubManifest,
                    timeout: githubTimeout
                ))
            }
            group.addTask {
                do {
                    try await Task.sleep(for: hedge.giteeStartDelay)
                    return .startGitee
                } catch {
                    return .githubDeadline
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: backupDeadline)
                    return .backupDeadline
                } catch {
                    return .startGitee
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: hedge.githubPrimaryDeadline)
                    return .githubDeadline
                } catch {
                    return .startGitee
                }
            }

            var giteeStarted = false
            var githubAvailability: UpdateSourceAvailabilityError?
            var giteeOutcome: ManifestFetchOutcome?
            var githubDeadlinePassed = false
            var lateGithubUpdate: AvailableUpdate?

            while let event = await group.next() {
                switch event {
                case .startGitee:
                    guard !giteeStarted else { continue }
                    giteeStarted = true
                    AutomaticUpdateLog.log("update.source.gitee.fallback.started")
                    group.addTask {
                        .gitee(await Self.fetchManifestOutcome(
                            sourceFetcher: sourceFetcher,
                            endpoint: .giteeManifest,
                            timeout: giteeTimeout
                        ))
                    }

                case .github(let outcome):
                    switch outcome {
                    case .succeeded(let update):
                        if !githubDeadlinePassed {
                            // GitHub remains authoritative whenever it returns
                            // a valid manifest before its primary deadline.
                            return .update(update)
                        }
                        // GitHub answered after its primary deadline. It is no
                        // longer allowed to preempt Gitee, but a valid result
                        // is kept as the backup-deadline fallback instead of
                        // being discarded when the mirror then fails.
                        lateGithubUpdate = update
                        AutomaticUpdateLog.log("update.source.github.lateValid")
                    case .invalid(let error):
                        if !githubDeadlinePassed {
                            AutomaticUpdateLog.log("update.source.github.invalid")
                            AutomaticUpdateLog.log("update.source.gitee.fallback.notAllowed")
                            return .failure(error)
                        }
                        // A late invalid GitHub response changes nothing; keep
                        // waiting for Gitee or the backup deadline.
                    case .availability(let error):
                        githubAvailability = error
                        AutomaticUpdateLog.log("update.source.github.unavailable")
                        if let giteeOutcome,
                           let decision = Self.decisionAfterGitHubAvailability(
                               giteeOutcome,
                               lateGithubUpdate: lateGithubUpdate
                           ) {
                            return decision
                        }
                        if !giteeStarted {
                            giteeStarted = true
                            AutomaticUpdateLog.log("update.source.gitee.fallback.started")
                            group.addTask {
                                .gitee(await Self.fetchManifestOutcome(
                                    sourceFetcher: sourceFetcher,
                                    endpoint: .giteeManifest,
                                    timeout: giteeTimeout
                                ))
                            }
                        }
                    }

                case .gitee(let outcome):
                    giteeOutcome = outcome
                    guard githubDeadlinePassed || githubAvailability != nil else { continue }
                    if case .succeeded(let update) = outcome {
                        return .update(update)
                    }
                    switch outcome {
                    case .availability:
                        // Both sources unreachable: fall back to the GitHub API
                        // without waiting for a slow primary response.
                        if let decision = Self.decisionAfterGitHubAvailability(
                            outcome,
                            lateGithubUpdate: lateGithubUpdate
                        ) {
                            return decision
                        }
                    case .invalid:
                        // A Gitee validation error alone should not fail the
                        // check while a valid late GitHub manifest may still
                        // arrive before the backup deadline.
                        if githubAvailability != nil,
                           let decision = Self.decisionAfterGitHubAvailability(
                               outcome,
                               lateGithubUpdate: lateGithubUpdate
                           ) {
                            return decision
                        }
                    case .succeeded:
                        break
                    }

                case .githubDeadline:
                    githubDeadlinePassed = true
                    if let giteeOutcome {
                        switch giteeOutcome {
                        case .succeeded(let update):
                            return .update(update)
                        case .availability:
                            if let decision = Self.decisionAfterGitHubAvailability(
                                giteeOutcome,
                                lateGithubUpdate: lateGithubUpdate
                            ) {
                                return decision
                            }
                        case .invalid:
                            // Wait for a valid late GitHub manifest or the
                            // backup deadline instead of failing immediately.
                            break
                        }
                    }
                    if !giteeStarted {
                        giteeStarted = true
                        AutomaticUpdateLog.log("update.source.gitee.fallback.started")
                        group.addTask {
                            .gitee(await Self.fetchManifestOutcome(
                                sourceFetcher: sourceFetcher,
                                endpoint: .giteeManifest,
                                timeout: giteeTimeout
                            ))
                        }
                    }
                    // GitHub is no longer allowed to hold the check open, but
                    // the already-started Gitee request gets the remainder of
                    // the backup window.

                case .backupDeadline:
                    if let giteeOutcome,
                       let decision = Self.decisionAfterGitHubAvailability(
                           giteeOutcome,
                           lateGithubUpdate: lateGithubUpdate
                       ) {
                        return decision
                    }
                    if let lateGithubUpdate {
                        AutomaticUpdateLog.log("update.source.github.lateValid")
                        return .update(lateGithubUpdate)
                    }
                    AutomaticUpdateLog.log("update.source.github.unavailable")
                    AutomaticUpdateLog.log("update.source.gitee.fallback.failed")
                    return .failure(.updateManifestUnavailable)
                }
            }

            return .failure(.updateManifestUnavailable)
        }
    }

    /// Single-source manifest fetch for a manual update-source preference.
    /// No hedging, no fallback: the pinned source decides.
    private func fetchSingleSource(
        endpoint: UpdateEndpoint,
        timeout: TimeInterval
    ) async -> ManifestHedgeDecision {
        let outcome = await Self.fetchManifestOutcome(
            sourceFetcher: sourceFetcher,
            endpoint: endpoint,
            timeout: timeout
        )
        switch outcome {
        case .succeeded(let update): return .update(update)
        case .availability: return .failure(.updateManifestUnavailable)
        case .invalid(let error): return .failure(error)
        }
    }

    private static func fetchManifestOutcome(
        sourceFetcher: UpdateSourceFetching,
        endpoint: UpdateEndpoint,
        timeout: TimeInterval
    ) async -> ManifestFetchOutcome {
        let source = endpoint.provider.rawValue
        AutomaticUpdateLog.log("update.source.\(source).started")
        do {
            let update = try await sourceFetcher.fetchManifest(endpoint: endpoint, timeout: timeout)
            AutomaticUpdateLog.log("update.source.\(source).succeeded")
            return .succeeded(update)
        } catch let error as UpdateSourceAvailabilityError {
            return .availability(error)
        } catch let error as AppUpdateError {
            if case .unsupportedSystemVersion = error {
                AutomaticUpdateLog.log("update.source.\(source).unsupportedSystemVersion")
            }
            return .invalid(error)
        } catch {
            return .invalid(.updateManifestUnavailable)
        }
    }

    private static func decisionAfterGitHubAvailability(
        _ outcome: ManifestFetchOutcome,
        lateGithubUpdate: AvailableUpdate?
    ) -> ManifestHedgeDecision? {
        switch outcome {
        case .succeeded(let update): return .update(update)
        case .availability:
            if let lateGithubUpdate {
                AutomaticUpdateLog.log("update.source.github.lateValid")
                return .update(lateGithubUpdate)
            }
            AutomaticUpdateLog.log("update.source.gitee.fallback.failed")
            return .apiFallback
        case .invalid(let error):
            if let lateGithubUpdate {
                AutomaticUpdateLog.log("update.source.github.lateValid")
                return .update(lateGithubUpdate)
            }
            AutomaticUpdateLog.log("update.source.gitee.invalid")
            AutomaticUpdateLog.log("update.source.gitee.fallback.notAllowed")
            return .failure(error)
        }
    }

    func fullReleaseNotes(for update: AvailableUpdate) async throws -> String? {
        let release = try await latestRelease()
        guard SemanticVersion.compare(release.version, update.version) == .orderedSame else {
            return nil
        }
        return try await releaseNotes(
            for: release,
            language: languageProvider()
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
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.isPrerelease, SemanticVersion.isStable(release.version) else {
            throw AppUpdateError.prereleaseNotSupported
        }
        return release
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

    /// `progress` receives transfer events for every source attempt in order
    /// (a fallback emits `.github` progress, then `.gitee` progress with the
    /// byte count restarted) and a final `.downloadCompleted` when the
    /// winning attempt's network transfer ends. A nil handler skips
    /// emission entirely.
    func prepare(
        _ update: AvailableUpdate,
        progress: UpdateDownloadEventHandler? = nil
    ) async throws -> PreparedAppUpdate {
        switch updateSourcePreference() {
        case .github:
            guard let githubAsset = update.assets.first(where: { $0.provider == .github }) else {
                throw AppUpdateError.noCompatibleAsset
            }
            AutomaticUpdateLog.log("update.download.github.pinned")
            // Pinned source: no slow-switch monitoring, no availability cache.
            return try await prepare(asset: githubAsset, for: update, progress: progress)
        case .gitee:
            guard let giteeAsset = update.assets.first(where: { $0.provider == .gitee }) else {
                throw AppUpdateError.noCompatibleAsset
            }
            AutomaticUpdateLog.log("update.download.gitee.pinned")
            return try await prepare(asset: giteeAsset, for: update, progress: progress)
        case .automatic:
            return try await prepareAutomatic(update, progress: progress)
        }
    }

    private func prepareAutomatic(
        _ update: AvailableUpdate,
        progress: UpdateDownloadEventHandler?
    ) async throws -> PreparedAppUpdate {
        let githubAsset = update.assets.first { $0.provider == .github }
        let giteeAsset = update.assets.first { $0.provider == .gitee }
        let manifestProvider = update.metadataSource.manifestProvider

        // A GitHub manifest must contain a GitHub asset. A Gitee fallback
        // manifest may contain only a Gitee asset, because it is already the
        // selected metadata source after GitHub was unavailable.
        guard githubAsset != nil || (manifestProvider == .gitee && giteeAsset != nil) else {
            throw AppUpdateError.noCompatibleAsset
        }

        // If the manifest was obtained from Gitee, this check already proved
        // GitHub unavailable in the current network environment. Reuse that
        // decision for the download instead of making a second 12-second
        // GitHub connection attempt. A short cache also covers the API
        // fallback path, while a later valid GitHub manifest clears it. A
        // separate download cache remembers a recently measured slow GitHub
        // transfer so the next check skips the re-measurement entirely.
        if let giteeAsset,
           manifestProvider == .gitee
               || isGitHubUnavailableCached()
               || isGitHubDownloadUnavailableCached() {
            return try await prepareGiteeAssetFirst(
                giteeAsset,
                githubAsset: githubAsset,
                update: update,
                progress: progress
            )
        }

        if let githubAsset {
            AutomaticUpdateLog.log("update.download.github.started")
            do {
                // Only monitor the GitHub-first path, and only when a Gitee
                // asset exists to fall back to. Without a mirror, a slow
                // transfer keeps running instead of aborting into an error.
                let prepared = try await prepare(
                    asset: githubAsset,
                    for: update,
                    slowSpeedPolicy: giteeAsset != nil ? downloadSourcePolicy : nil,
                    progress: progress
                )
                githubDownloadUnavailableUntil = nil
                AutomaticUpdateLog.log("update.download.verified")
                return prepared
            } catch let error as UpdateSourceAvailabilityError {
                if case .downloadTooSlow = error {
                    AutomaticUpdateLog.log("update.download.github.tooSlow")
                }
                AutomaticUpdateLog.log("update.download.github.unavailable")
                guard let giteeAsset else {
                    throw AppUpdateError.updateSourcesUnavailable
                }
                AutomaticUpdateLog.log("update.download.gitee.fallback.started")
                do {
                    let prepared = try await prepare(asset: giteeAsset, for: update, progress: progress)
                    if case .downloadTooSlow = error {
                        githubDownloadUnavailableUntil = Date()
                            .addingTimeInterval(Self.githubUnavailableCacheDuration)
                        AutomaticUpdateLog.log("update.download.gitee.switched")
                    }
                    AutomaticUpdateLog.log("update.download.verified")
                    return prepared
                } catch is UpdateSourceAvailabilityError {
                    AutomaticUpdateLog.log("update.download.gitee.fallback.failed")
                    throw AppUpdateError.updateSourcesUnavailable
                } catch {
                    logIntegrityOrConfigurationFailure(error, provider: .gitee)
                    throw error
                }
            } catch {
                logIntegrityOrConfigurationFailure(error, provider: .github)
                throw error
            }
        }

        guard let giteeAsset else { throw AppUpdateError.noCompatibleAsset }
        AutomaticUpdateLog.log("update.download.gitee.started")
        do {
            let prepared = try await prepare(asset: giteeAsset, for: update, progress: progress)
            AutomaticUpdateLog.log("update.download.verified")
            return prepared
        } catch is UpdateSourceAvailabilityError {
            AutomaticUpdateLog.log("update.download.gitee.failed")
            throw AppUpdateError.updateSourcesUnavailable
        } catch {
            logIntegrityOrConfigurationFailure(error, provider: .gitee)
            throw error
        }
    }

    private func prepareGiteeAssetFirst(
        _ giteeAsset: UpdateAsset,
        githubAsset: UpdateAsset?,
        update: AvailableUpdate,
        progress: UpdateDownloadEventHandler?
    ) async throws -> PreparedAppUpdate {
        AutomaticUpdateLog.log("update.download.gitee.started")
        do {
            let prepared = try await prepare(asset: giteeAsset, for: update, progress: progress)
            AutomaticUpdateLog.log("update.download.verified")
            return prepared
        } catch is UpdateSourceAvailabilityError {
            AutomaticUpdateLog.log("update.download.gitee.unavailable")
            guard let githubAsset else {
                throw AppUpdateError.updateSourcesUnavailable
            }
            AutomaticUpdateLog.log("update.download.github.fallback.started")
            do {
                let prepared = try await prepare(asset: githubAsset, for: update, progress: progress)
                AutomaticUpdateLog.log("update.download.verified")
                return prepared
            } catch is UpdateSourceAvailabilityError {
                AutomaticUpdateLog.log("update.download.github.fallback.failed")
                throw AppUpdateError.updateSourcesUnavailable
            } catch {
                logIntegrityOrConfigurationFailure(error, provider: .github)
                throw error
            }
        } catch {
            logIntegrityOrConfigurationFailure(error, provider: .gitee)
            throw error
        }
    }

    private func updateGitHubAvailabilityCache(for update: AvailableUpdate) {
        if update.metadataSource.manifestProvider == .gitee {
            githubUnavailableUntil = Date().addingTimeInterval(Self.githubUnavailableCacheDuration)
        } else {
            githubUnavailableUntil = nil
        }
    }

    private func isGitHubUnavailableCached() -> Bool {
        guard let githubUnavailableUntil else { return false }
        guard githubUnavailableUntil > Date() else {
            self.githubUnavailableUntil = nil
            return false
        }
        return true
    }

    private func isGitHubDownloadUnavailableCached() -> Bool {
        guard let githubDownloadUnavailableUntil else { return false }
        guard githubDownloadUnavailableUntil > Date() else {
            self.githubDownloadUnavailableUntil = nil
            return false
        }
        return true
    }

    func discard(_ update: PreparedAppUpdate) {
        try? detach(update.mountPoint)
        try? fileManager.removeItem(at: update.dmgURL.deletingLastPathComponent())
    }

    /// `slowSpeedPolicy` enables sustained-slow detection during the body
    /// transfer. Only the GitHub-first path passes a policy (when a Gitee
    /// asset exists to fall back to); the reverse direction never monitors.
    /// `progress` forwards every transfer snapshot with the asset's provider.
    private func prepare(
        asset: UpdateAsset,
        for update: AvailableUpdate,
        slowSpeedPolicy: DownloadSourcePolicy? = nil,
        progress: UpdateDownloadEventHandler? = nil
    ) async throws -> PreparedAppUpdate {
        if let assetPreparer {
            return try await assetPreparer(asset, update)
        }

        guard asset.downloadURL.scheme?.lowercased() == "https", asset.downloadURL.host != nil else {
            throw AppUpdateError.invalidDownloadURL
        }

        // Keep a long resource timeout for slow DMG transfers. The helper below
        // races only the first HTTP response against a short connection window;
        // once headers arrive, the body is streamed without using that short
        // window as the total download timeout.
        var request = URLRequest(url: asset.downloadURL, timeoutInterval: 120)
        request.setValue("YuanGUI/\(AppVersionInfo.version)", forHTTPHeaderField: "User-Agent")

        let updateDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("YuanGUI-Update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        let fileName = asset.downloadURL.lastPathComponent.isEmpty ? "YuanGUI-update.dmg" : asset.downloadURL.lastPathComponent
        let dmgURL = updateDirectory.appendingPathComponent(fileName)

        do {
            _ = try await streamDownload(
                request,
                to: dmgURL,
                expectedBytes: asset.size,
                slowSpeedPolicy: slowSpeedPolicy,
                provider: asset.provider,
                progressHandler: progress
            )
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

    // Internal for deterministic URLProtocol coverage of first-response and
    // streamed-body handling; callers still enter through prepare(_:).
    func streamDownload(
        _ request: URLRequest,
        to destination: URL,
        expectedBytes: Int64? = nil,
        slowSpeedPolicy: DownloadSourcePolicy? = nil,
        provider: UpdateAsset.Provider = .other,
        progressHandler: UpdateDownloadEventHandler? = nil
    ) async throws -> URLResponse {
        let session = self.session
        let (bytes, response) = try await withThrowingTaskGroup(
            of: (URLSession.AsyncBytes, URLResponse).self,
            returning: (URLSession.AsyncBytes, URLResponse).self
        ) { group in
            defer { group.cancelAll() }
            group.addTask {
                try await session.bytes(for: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw UpdateSourceAvailabilityError.timedOut
            }
            guard let first = try await group.next() else {
                throw UpdateSourceAvailabilityError.resourceUnavailable
            }
            return first
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if UpdateSourceAvailabilityError.isFallbackHTTPStatus(http.statusCode) {
                throw UpdateSourceAvailabilityError.httpStatus(http.statusCode)
            }
            throw AppUpdateError.invalidResponse
        }

        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: destination)
        let progress = DownloadProgressTracker()
        // Only the writer may end the transfer with `.writerFinished`. The
        // monitors return nil (cancelled, or the transfer is already
        // complete) and throw on slow/stalled transfers, so `group.next()`
        // can never mistake a monitor for a finished download and cancel the
        // writer mid-flush.
        enum DownloadStreamEvent: Sendable {
            case writerFinished
        }
        // The manifest's asset size is authoritative; the HTTP response's
        // content length is the fallback when the caller has no expected
        // size. When both are unknown the UI shows indeterminate progress.
        let totalBytes: Int64? = expectedBytes ?? {
            let length = response.expectedContentLength
            return length >= 0 ? length : nil
        }()
        // UI reporting is a side path: the writer only yields snapshots into
        // this buffer — it never awaits a consumer. A dedicated drain task
        // invokes the handler, so a busy MainActor can neither stall the
        // transfer nor slow it enough to trip the sustained-slow GitHub →
        // Gitee monitor. The drain is flushed once when the attempt ends
        // (success or abort), which both delivers `.downloadCompleted` before
        // verification starts and guarantees no snapshot of a failed attempt
        // leaks into the fallback attempt's events.
        let (eventStream, eventContinuation) = AsyncStream<UpdateDownloadEvent>.makeStream()
        let reportProgress: @Sendable (Int64) -> Void = { [provider, totalBytes, eventContinuation] receivedBytes in
            eventContinuation.yield(.progress(UpdateDownloadProgress(
                provider: provider,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes
            )))
        }
        var drainTask: Task<Void, Never>?
        if let progressHandler {
            drainTask = Task {
                for await event in eventStream {
                    await progressHandler(event)
                }
            }
        }
        do {
            try await withThrowingTaskGroup(of: DownloadStreamEvent?.self) { group in
                defer { group.cancelAll() }
                group.addTask {
                    var buffer = Data()
                    var bytesSinceProgressMark = 0
                    var totalBytesRead: Int64 = 0
                    // Snapshot throttle: the slow/stall monitors keep their
                    // own sampling, so this exists purely to keep SwiftUI
                    // publishing near ~10 events per second.
                    var lastUIProgressAt = Date.distantPast
                    buffer.reserveCapacity(64 * 1024)
                    for try await byte in bytes {
                        buffer.append(byte)
                        totalBytesRead += 1
                        bytesSinceProgressMark += 1
                        if buffer.count >= 64 * 1024 {
                            try handle.write(contentsOf: buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                        if bytesSinceProgressMark >= 16 * 1024 {
                            await progress.markProgress(bytes: totalBytesRead)
                            bytesSinceProgressMark = 0
                            let now = Date()
                            if now.timeIntervalSince(lastUIProgressAt) >= 0.1 {
                                lastUIProgressAt = now
                                reportProgress(totalBytesRead)
                            }
                        }
                    }
                    // Publish the final byte count before the tail flush so a
                    // monitor waking mid-flush sees a complete transfer.
                    await progress.markProgress(bytes: totalBytesRead)
                    if !buffer.isEmpty {
                        try handle.write(contentsOf: buffer)
                    }
                    // Final snapshot: even when the throttle suppressed the
                    // last mark, the UI must see the completed transfer (100%
                    // whenever the total is known).
                    reportProgress(totalBytesRead)
                    // The network transfer is over; everything after this
                    // point (verification, mounting) belongs to .installing.
                    eventContinuation.yield(.downloadCompleted)
                    return DownloadStreamEvent.writerFinished
                }
                group.addTask {
                    do {
                        while true {
                            try await Task.sleep(for: .seconds(25))
                            if await progress.isStale(after: 25) {
                                throw UpdateSourceAvailabilityError.timedOut
                            }
                        }
                    } catch is CancellationError {
                        return nil
                    }
                }
                if let policy = slowSpeedPolicy {
                    group.addTask {
                        do {
                            while true {
                                try await Task.sleep(for: .seconds(policy.sampleInterval))
                                // Completeness first: once every byte is
                                // marked, the writer is finishing its last
                                // writes and must never be judged slow.
                                if let expectedBytes,
                                   await progress.totalBytesRead() >= expectedBytes {
                                    return nil
                                }
                                if await progress.isSlow(
                                    under: policy.minimumRateBytesPerSecond,
                                    window: policy.observationWindow
                                ) {
                                    throw UpdateSourceAvailabilityError.downloadTooSlow
                                }
                            }
                        } catch is CancellationError {
                            return nil
                        }
                    }
                }
                while let event = try await group.next() {
                    if event == .writerFinished {
                        return
                    }
                }
            }
            // Flush the reporting side path before returning so the store
            // learns `.downloadCompleted` before verification begins. The
            // transfer is already done here; waiting for the drain costs no
            // download time.
            eventContinuation.finish()
            await drainTask?.value
            try handle.close()
        } catch {
            // End the attempt's stream and drain whatever it buffered so no
            // snapshot of this (failed) attempt leaks into a fallback's
            // event sequence.
            eventContinuation.finish()
            await drainTask?.value
            try? handle.close()
            if let availabilityError = error as? UpdateSourceAvailabilityError {
                throw availabilityError
            }
            if let urlError = error as? URLError {
                throw UpdateSourceAvailabilityError(urlError: urlError) ?? urlError
            }
            throw error
        }
        return response
    }

    private func logIntegrityOrConfigurationFailure(
        _ error: Error,
        provider: UpdateAsset.Provider
    ) {
        switch error {
        case AppUpdateError.checksumMismatch,
             AppUpdateError.checksumUnavailable,
             AppUpdateError.assetSizeMismatch,
             AppUpdateError.dmgMissing,
             AppUpdateError.mountFailed,
             AppUpdateError.appMissing,
             AppUpdateError.invalidBundle,
             AppUpdateError.invalidVersion,
             AppUpdateError.invalidBuild,
             AppUpdateError.unsupportedSystemVersion,
             AppUpdateError.invalidSignature,
             AppUpdateError.installLocationNotWritable,
             AppUpdateError.invalidDownloadURL:
            AutomaticUpdateLog.log("update.download.integrityValidationFailed")
        default:
            AutomaticUpdateLog.log("update.download.\(provider.rawValue).failed")
        }
        AutomaticUpdateLog.log("update.download.fallback.notAllowed")
    }

    private func verifyDownloadedAsset(at url: URL, asset: UpdateAsset) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        if let expectedSize = asset.size, actualSize != expectedSize {
            throw AppUpdateError.assetSizeMismatch
        }
        guard let expectedHash = asset.sha256 else { throw AppUpdateError.checksumUnavailable }
        let actualHash = try sha256(of: url)
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
        guard let bundledMinimumSystemVersion = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
              SemanticVersion.isStable(bundledMinimumSystemVersion)
        else {
            throw AppUpdateError.invalidBundle
        }
        guard SemanticVersion.compare(currentSystemVersion(), bundledMinimumSystemVersion) != .orderedAscending else {
            throw AppUpdateError.unsupportedSystemVersion
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

/// Outcome of publishing an automatic check's result into the store. The
/// automatic coordinator uses the cases to log the exact reason a commit was
/// skipped.
enum AutomaticUpdateCommitResult: Sendable, Equatable {
    case committed
    case busy
    case staleSource
}

@MainActor
final class AppUpdateStore: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, available, downloading, installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestUpdate: AvailableUpdate?
    @Published private(set) var latestUpdateNotes: String?
    /// Current DMG transfer snapshot, non-nil only while `.downloading`. A
    /// fallback replaces it with the new provider's progress (bytes restarted
    /// from zero); `.installing` and `.failed` clear it.
    @Published private(set) var downloadProgress: UpdateDownloadProgress?
    @Published private(set) var updateSourcePreference: UpdateSourcePreference = .automatic
    /// Bumped on every source-preference switch. An automatic check captures
    /// the revision when it starts and passes it back at commit time; a
    /// mismatch means the check began under an older source and its result
    /// must be discarded instead of overwriting the newer check's outcome.
    private(set) var updateSourceRevision: UInt64 = 0
    private let service: AppUpdateService
    private let checking: UpdateChecking
    private let defaults: UserDefaults
    private var terminateForUpdate: @MainActor () async -> Bool = { false }
    private var notesTask: Task<Void, Never>?

    /// Test seam: replaces the DMG download/install pipeline. When set,
    /// `installLatest()` runs this closure instead of touching the network,
    /// so tests can observe install attempts without real downloads.
    var installLauncher: ((AvailableUpdate) async throws -> Void)?

    init(service: AppUpdateService = AppUpdateService(), checking: UpdateChecking? = nil, defaults: UserDefaults = .standard) {
        self.service = service
        self.checking = checking ?? service
        self.defaults = defaults
        self.updateSourcePreference = UpdateSourcePreference(
            rawValue: defaults.string(forKey: UpdateSourcePreference.storageKey) ?? ""
        ) ?? .automatic
    }

    func setUpdateSourcePreference(_ preference: UpdateSourcePreference) {
        guard updateSourcePreference != preference else { return }
        // Switching mid-check/download/install is unsafe. The About picker
        // is disabled while busy; this guard also covers programmatic calls.
        guard !isBusy else { return }
        updateSourcePreference = preference
        defaults.set(preference.rawValue, forKey: UpdateSourcePreference.storageKey)
        updateSourceRevision += 1
        // The previous check result belongs to the old source and may lack
        // the new source's asset; installing it under the new preference
        // would fail with noCompatibleAsset. Discard the stale result and
        // re-check immediately against the pinned source.
        notesTask?.cancel()
        notesTask = nil
        latestUpdate = nil
        latestUpdateNotes = nil
        state = .idle
        check()
    }

    var isBusy: Bool { state == .checking || state == .downloading || state == .installing }

    func setTerminationHandler(_ handler: @escaping @MainActor () async -> Bool) {
        terminateForUpdate = handler
    }

    func check() {
        guard !isBusy else { return }
        notesTask?.cancel()
        notesTask = nil
        state = .checking
        latestUpdate = nil
        latestUpdateNotes = nil
        Task {
            do {
                let result = try await checking.checkForUpdate(mode: .manual)
                switch result {
                case .available(let update, let notes):
                    latestUpdate = update
                    latestUpdateNotes = notes
                    state = .available
                    enrichReleaseNotesIfNeeded(for: update)
                case .upToDate(let update):
                    latestUpdate = update
                    latestUpdateNotes = update.localizedHighlights.map { "- \($0)" }.joined(separator: "\n")
                    state = .upToDate
                    enrichReleaseNotesIfNeeded(for: update)
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func enrichReleaseNotesIfNeeded(for update: AvailableUpdate) {
        guard update.metadataSource != .githubReleaseAPI else { return }
        notesTask?.cancel()
        notesTask = Task { [weak self, service] in
            guard let notes = try? await service.fullReleaseNotes(for: update),
                  !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !Task.isCancelled
            else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      self.latestUpdate == update,
                      self.state == .available || self.state == .upToDate
                else { return }
                self.latestUpdateNotes = notes
            }
        }
    }

    /// Publishes an update discovered by the automatic coordinator without
    /// moving the store through `.checking` or surfacing an error. Returns
    /// `.busy` when a manual check or install is already in flight and
    /// `.staleSource` when `expectedSourceRevision` does not equal
    /// `updateSourceRevision` — a check that started before a source-
    /// preference switch reports a stale result and is discarded.
    @discardableResult
    func commitAutomaticUpdate(
        release: AvailableUpdate,
        notes: String?,
        expectedSourceRevision: UInt64
    ) -> AutomaticUpdateCommitResult {
        guard !isBusy else { return .busy }
        guard expectedSourceRevision == updateSourceRevision else { return .staleSource }
        latestUpdate = release
        latestUpdateNotes = notes
        state = .available
        return .committed
    }

    func installLatest() {
        guard let release = latestUpdate, AppVersionInfo.isNewer(release) else { return }
        guard !isBusy else { return }
        state = .downloading
        downloadProgress = nil
        Task {
            do {
                if let installLauncher {
                    try await installLauncher(release)
                    downloadProgress = nil
                    state = .installing
                    return
                }
                let prepared = try await service.prepare(release) { [weak self] event in
                    // The callback runs on the service's drain task, never on
                    // the download writer, and is flushed before prepare
                    // returns — so a busy MainActor cannot slow the transfer.
                    // The store hops to MainActor to touch published state;
                    // binding the weak reference to a local first keeps the
                    // nested closure capture immutable.
                    let store = self
                    await MainActor.run {
                        guard let store else { return }
                        switch event {
                        case .progress(let progress):
                            store.downloadProgress = progress
                        case .downloadCompleted:
                            // The network transfer ended; verification,
                            // mounting, and signing happen under .installing.
                            // The guard also absorbs a late event racing the
                            // store's own .installing transition below.
                            store.downloadProgress = nil
                            if store.state == .downloading {
                                store.state = .installing
                            }
                        }
                    }
                }
                downloadProgress = nil
                state = .installing
                guard await terminateForUpdate() else {
                    await service.discard(prepared)
                    downloadProgress = nil
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
                downloadProgress = nil
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
