import AppKit
import CoreServices
import Foundation

struct MaintenanceScanProgress: Equatable {
    let completed: Int
    let total: Int
    let message: String
}

protocol CleanupScanning {
    func scan(
        excluding paths: Set<String>,
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [CleanupCandidate]
    func scanApplications(
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [ApplicationCandidate]
}

extension CleanupScanning {
    func scan(
        configuration: CleanupScanConfiguration,
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [CleanupCandidate] {
        await scan(excluding: Set(configuration.whitelistedPaths), progress: progress)
    }

    func scan(excluding paths: Set<String>) async -> [CleanupCandidate] {
        await scan(excluding: paths, progress: { _ in })
    }

    func scanApplications() async -> [ApplicationCandidate] {
        await scanApplications(progress: { _ in })
    }
}

protocol MaintenanceHandling {
    func clean(_ candidates: [CleanupCandidate]) async -> MaintenanceOperation
    func uninstall(_ applications: [ApplicationCandidate]) async -> MaintenanceOperation
}

private struct CleanupRule {
    let root: URL
    let category: CleanupCategory
    let disposition: CleanupDisposition
    let minimumAgeDays: Int?
    let risk: MaintenanceRisk
    let selectedByDefault: Bool
    let reason: String
}

private actor ScanProgressCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private struct ApplicationMetadata: Codable {
    let path: String
    let modificationDate: Date?
    let byteCount: Int64
    let lastUsedAt: Date?
    let cachedAt: Date
}

private final class ApplicationMetadataCache {
    private let fileURL: URL
    private var values: [String: ApplicationMetadata]
    private let lock = NSLock()

    init(fileManager: FileManager = .default, rootOverride: URL? = nil) {
        let root = rootOverride ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuanGUI", isDirectory: true)
        fileURL = root.appendingPathComponent("application-metadata-v1.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: ApplicationMetadata].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    func value(for url: URL, modificationDate: Date?, now: Date = Date()) -> ApplicationMetadata? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[url.standardizedFileURL.path],
              value.modificationDate == modificationDate,
              now.timeIntervalSince(value.cachedAt) < 7 * 24 * 60 * 60 else { return nil }
        return value
    }

    func set(_ value: ApplicationMetadata) {
        lock.lock()
        values[value.path] = value
        lock.unlock()
    }

    func persist(fileManager: FileManager = .default) {
        lock.lock()
        let snapshot = values
        lock.unlock()
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Metadata caching is only a performance optimization.
        }
    }
}

struct CleanupScanner: CleanupScanning {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let metadataCache: ApplicationMetadataCache
    private let userLibraryOverride: URL?
    private let temporaryDirectoryOverride: URL?
    private let applicationRootsOverride: [(url: URL, source: ApplicationSource)]?
    private let homeDirectoryOverride: URL?
    private let downloadsDirectoryOverride: URL?
    private let desktopDirectoryOverride: URL?

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        userLibrary: URL? = nil,
        temporaryDirectory: URL? = nil,
        applicationRoots: [(URL, ApplicationSource)]? = nil,
        metadataCacheRoot: URL? = nil,
        homeDirectory: URL? = nil,
        downloadsDirectory: URL? = nil,
        desktopDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.userLibraryOverride = userLibrary
        self.temporaryDirectoryOverride = temporaryDirectory
        self.applicationRootsOverride = applicationRoots?.map { (url: $0.0, source: $0.1) }
        self.metadataCache = ApplicationMetadataCache(fileManager: fileManager, rootOverride: metadataCacheRoot)
        self.homeDirectoryOverride = homeDirectory
        self.downloadsDirectoryOverride = downloadsDirectory
        self.desktopDirectoryOverride = desktopDirectory
    }

    func scan(
        excluding paths: Set<String>,
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [CleanupCandidate] {
        await scanStandardCategories(
            nil,
            excluding: paths,
            progress: progress
        )
    }

    private func scanStandardCategories(
        _ enabledCategories: Set<CleanupCategory>?,
        excluding paths: Set<String>,
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [CleanupCandidate] {
        let rules = cleanupRules().filter { rule in
            guard let enabledCategories else { return true }
            return enabledCategories.contains(rule.category)
                || (rule.category == .appCache && enabledCategories.contains(.browserCache))
        }
        let scansOrphanedData = enabledCategories?.contains(.orphanedAppData) ?? true
        let total = rules.count + (scansOrphanedData ? 1 : 0)
        let counter = ScanProgressCounter()
        let lanes = (0..<min(2, rules.count)).map { start in
            stride(from: start, to: rules.count, by: 2).map { rules[$0] }
        }

        var candidates = await withTaskGroup(of: [CleanupCandidate].self) { group in
            for lane in lanes {
                group.addTask(priority: .utility) {
                    var laneResults: [CleanupCandidate] = []
                    for rule in lane {
                        guard !Task.isCancelled else { break }
                        laneResults += scanChildren(rule: rule, excluding: paths)
                        let value = await counter.increment()
                        progress(MaintenanceScanProgress(
                            completed: value,
                            total: total,
                            message: AppLocalizer.format("maintenance.progress.scanningCategory", rule.category.title)
                        ))
                    }
                    return laneResults
                }
            }
            var merged: [CleanupCandidate] = []
            for await values in group { merged += values }
            return merged
        }

        if scansOrphanedData, !Task.isCancelled {
            candidates += scanOrphanedData(excluding: paths)
            progress(MaintenanceScanProgress(completed: total, total: total, message: AppLocalizer.string("maintenance.progress.organizing")))
        }
        if let enabledCategories {
            candidates.removeAll { !enabledCategories.contains($0.category) }
        }
        return deduplicated(candidates).sorted { $0.byteCount > $1.byteCount }
    }

    func scan(
        configuration: CleanupScanConfiguration,
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [CleanupCandidate] {
        var candidates = await scanStandardCategories(
            configuration.enabledCategories,
            excluding: Set(configuration.whitelistedPaths),
            progress: progress
        )
        guard !Task.isCancelled else { return candidates }

        if configuration.enabledCategories.contains(.developerCache) {
            candidates += scanDeveloperToolCaches(excluding: Set(configuration.whitelistedPaths))
        }
        if configuration.enabledCategories.contains(.projectBuildArtifact) {
            candidates += scanProjectArtifacts(configuration: configuration)
        }
        if configuration.enabledCategories.contains(.oldInstallerPackage) {
            candidates += scanOldInstallerPackages(excluding: Set(configuration.whitelistedPaths))
        }
        return deduplicated(candidates).sorted { $0.byteCount > $1.byteCount }
    }

    func scanApplications(
        progress: @escaping (MaintenanceScanProgress) -> Void
    ) async -> [ApplicationCandidate] {
        await Task.detached(priority: .utility) {
            let roots = applicationRoots()
            var discovered: [(url: URL, source: ApplicationSource)] = []
            var seen: Set<String> = []
            for root in roots {
                guard let apps = try? fileManager.contentsOfDirectory(
                    at: root.url,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for app in apps where app.pathExtension.lowercased() == "app" {
                    let path = app.standardizedFileURL.path
                    if seen.insert(path).inserted { discovered.append((app, root.source)) }
                }
            }

            let total = discovered.count
            var records: [(url: URL, source: ApplicationSource, name: String, bundleID: String, metadata: ApplicationMetadata, management: ApplicationManagement, warnings: [String], blocked: Bool)] = []
            for (index, item) in discovered.enumerated() {
                guard !Task.isCancelled else { break }
                guard let bundle = Bundle(url: item.url),
                      let bundleID = bundle.bundleIdentifier,
                      !bundleID.hasPrefix("com.apple."),
                      bundleID != "com.yang.yuangui" else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? item.url.deletingPathExtension().lastPathComponent
                let metadata = applicationMetadata(for: item.url)
                let management = applicationManagement(for: item.url, source: item.source)
                var warnings: [String] = []
                var blocked = false
                if management == .homebrew {
                    warnings.append(AppLocalizer.string("maintenance.warning.homebrew"))
                    blocked = true
                } else if management == .setapp {
                    warnings.append(AppLocalizer.string("maintenance.warning.setapp"))
                    blocked = true
                }
                if hasSystemLevelComponents(app: item.url, bundleID: bundleID) {
                    warnings.append(AppLocalizer.string("maintenance.warning.systemComponent"))
                    blocked = true
                }
                records.append((item.url, item.source, name, bundleID, metadata, management, warnings, blocked))
                progress(MaintenanceScanProgress(
                    completed: index + 1,
                    total: total,
                    message: AppLocalizer.format("maintenance.progress.readingApp", name)
                ))
            }
            metadataCache.persist(fileManager: fileManager)

            let bundleCounts = Dictionary(grouping: records, by: { $0.bundleID }).mapValues(\.count)
            let results = records.map { record -> ApplicationCandidate in
                let siblingExists = (bundleCounts[record.bundleID] ?? 0) > 1
                var warnings = record.warnings
                if siblingExists {
                    warnings.append(AppLocalizer.string("maintenance.warning.sharedBundleID"))
                }
                let components = uninstallComponents(
                    app: record.url,
                    name: record.name,
                    bundleID: record.bundleID,
                    appSize: record.metadata.byteCount,
                    includeResiduals: !siblingExists && !record.blocked
                )
                return ApplicationCandidate(
                    url: record.url,
                    name: record.name,
                    bundleIdentifier: record.bundleID,
                    byteCount: record.metadata.byteCount,
                    lastUsedAt: record.metadata.lastUsedAt,
                    components: components,
                    source: record.source,
                    management: record.management,
                    warnings: warnings,
                    removalBlocked: record.blocked
                )
            }
            return results.sorted {
                if $0.lastUsedAt != $1.lastUsedAt {
                    return ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast)
                }
                return $0.reclaimableByteCount > $1.reclaimableByteCount
            }
        }.value
    }

    private func cleanupRules() -> [CleanupRule] {
        let library = userLibraryDirectory
        return [
            CleanupRule(
                root: library.appendingPathComponent("Caches"), category: .appCache,
                disposition: .permanent, minimumAgeDays: nil, risk: .recommended,
                selectedByDefault: true, reason: AppLocalizer.string("maintenance.reason.appCache")
            ),
            CleanupRule(
                root: library.appendingPathComponent("Logs"), category: .oldLog,
                disposition: .permanent, minimumAgeDays: 7, risk: .recommended,
                selectedByDefault: true, reason: AppLocalizer.string("maintenance.reason.oldLog")
            ),
            CleanupRule(
                root: library.appendingPathComponent("Logs/DiagnosticReports"), category: .crashReport,
                disposition: .permanent, minimumAgeDays: 14, risk: .recommended,
                selectedByDefault: true, reason: AppLocalizer.string("maintenance.reason.crashReport")
            ),
            CleanupRule(
                root: temporaryDirectoryOverride ?? fileManager.temporaryDirectory, category: .temporary,
                disposition: .permanent, minimumAgeDays: 7, risk: .review,
                selectedByDefault: false, reason: AppLocalizer.string("maintenance.reason.temporary")
            ),
            CleanupRule(
                root: library.appendingPathComponent("Developer/Xcode/DerivedData"), category: .developerCache,
                disposition: .permanent, minimumAgeDays: nil, risk: .review,
                selectedByDefault: false, reason: AppLocalizer.string("maintenance.reason.xcodeBuild")
            ),
            CleanupRule(
                root: library.appendingPathComponent("Developer/Xcode/DerivedData/ModuleCache.noindex"), category: .developerCache,
                disposition: .permanent, minimumAgeDays: nil, risk: .review,
                selectedByDefault: false, reason: AppLocalizer.string("maintenance.reason.xcodeModuleCache")
            )
        ]
    }

    /// Rules adapted from Mole's checked source revision
    /// 27123a964aa671d2e64222634d29d4bd2dc866ed. This native implementation
    /// intentionally keeps only user-scoped, reproducible caches; it performs
    /// no shell commands, sudo actions, service resets, or system optimization.
    private func scanDeveloperToolCaches(excluding paths: Set<String>) -> [CleanupCandidate] {
        let home = homeDirectory
        let library = userLibraryDirectory
        let roots: [(URL, String)] = [
            (home.appendingPathComponent(".npm/_cacache"), "npm"),
            (home.appendingPathComponent(".cache/pip"), "pip"),
            (home.appendingPathComponent(".cache/uv"), "uv"),
            (home.appendingPathComponent(".cargo/registry"), "Cargo"),
            (home.appendingPathComponent("go/pkg/mod/cache"), "Go module"),
            (home.appendingPathComponent(".gradle/caches"), "Gradle"),
            (home.appendingPathComponent("Library/Caches/CocoaPods"), "CocoaPods"),
            (library.appendingPathComponent("Caches/Homebrew"), "Homebrew"),
            (library.appendingPathComponent("Developer/Xcode/DerivedData"), "Xcode DerivedData")
        ]
        return roots.compactMap { root, reason in
            guard !Task.isCancelled,
                  fileManager.fileExists(atPath: root.path),
                  !pathsContain(root.standardizedFileURL.path, in: paths),
                  !isSymbolicLink(root) else { return nil }
            let size = allocatedSize(of: root)
            guard size > 0 else { return nil }
            let values = try? root.resourceValues(forKeys: [.contentModificationDateKey])
            return CleanupCandidate(
                url: root,
                displayName: root.lastPathComponent,
                category: .developerCache,
                disposition: .permanent,
                byteCount: size,
                modifiedAt: values?.contentModificationDate,
                risk: .review,
                confidence: .exact,
                reason: AppLocalizer.format("maintenance.reason.rebuildableCache", reason),
                selectedByDefault: false
            )
        }
    }

    private func scanProjectArtifacts(configuration: CleanupScanConfiguration) -> [CleanupCandidate] {
        let excluded = Set(configuration.whitelistedPaths)
        var results: [CleanupCandidate] = []
        var rootsSeen: Set<String> = []
        for rootPath in configuration.projectRoots {
            guard !Task.isCancelled else { break }
            let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
            let normalizedRoot = root.resolvingSymlinksInPath()
            guard normalizedRoot.path != homeDirectory.standardizedFileURL.path,
                  rootsSeen.insert(normalizedRoot.path).inserted,
                  fileManager.fileExists(atPath: normalizedRoot.path),
                  !isSymbolicLink(root) else { continue }
            // Check the common project-root layout directly before recursive
            // traversal. It also covers hidden artifacts such as `.build` and
            // `.next`, which Finder-style directory enumeration may omit.
            if let projects = try? fileManager.contentsOfDirectory(
                at: normalizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) {
                for project in projects where !isSymbolicLink(project) {
                    for artifactName in projectArtifactNames {
                        let artifact = project.appendingPathComponent(artifactName, isDirectory: true)
                        var isDirectory: ObjCBool = false
                        guard fileManager.fileExists(atPath: artifact.path, isDirectory: &isDirectory),
                              isDirectory.boolValue,
                              !isSymbolicLink(artifact),
                              !pathsContain(artifact.standardizedFileURL.path, in: excluded) else { continue }
                        let size = allocatedSize(of: artifact)
                        guard size > 0 else { continue }
                        let values = try? artifact.resourceValues(forKeys: [.contentModificationDateKey])
                        results.append(CleanupCandidate(
                            url: artifact,
                            displayName: "\(project.lastPathComponent)/\(artifactName)",
                            category: .projectBuildArtifact,
                            disposition: .recycle,
                            byteCount: size,
                            modifiedAt: values?.contentModificationDate,
                            risk: .review,
                            confidence: .inferred,
                            reason: AppLocalizer.string("maintenance.reason.projectArtifact"),
                            selectedByDefault: false,
                            executionRoot: normalizedRoot
                        ))
                    }
                }
            }
            guard let enumerator = fileManager.enumerator(
                at: normalizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) else { continue }
            for case let url as URL in enumerator {
                guard !Task.isCancelled else { return results }
                let path = url.standardizedFileURL.path
                let depth = url.pathComponents.count - normalizedRoot.pathComponents.count
                if depth > 8 { enumerator.skipDescendants(); continue }
                if url.lastPathComponent.hasPrefix("."), !projectArtifactNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values?.isDirectory == true,
                      projectArtifactNames.contains(url.lastPathComponent),
                      !pathsContain(path, in: excluded),
                      isProjectArtifact(url, boundedBy: normalizedRoot) else { continue }
                let size = allocatedSize(of: url)
                guard size > 0 else { enumerator.skipDescendants(); continue }
                results.append(CleanupCandidate(
                    url: url,
                    displayName: "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)",
                    category: .projectBuildArtifact,
                    disposition: .recycle,
                    byteCount: size,
                    modifiedAt: values?.contentModificationDate,
                    risk: .review,
                    confidence: .inferred,
                    reason: AppLocalizer.string("maintenance.reason.projectArtifact"),
                    selectedByDefault: false,
                    executionRoot: normalizedRoot
                ))
                enumerator.skipDescendants()
            }
        }
        return results
    }

    private func scanOldInstallerPackages(excluding paths: Set<String>) -> [CleanupCandidate] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "ipsw"]
        let roots = [downloadsDirectory, desktopDirectory]
        var results: [CleanupCandidate] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard !Task.isCancelled else { return results }
                let depth = url.pathComponents.count - root.pathComponents.count
                if depth > 2 { enumerator.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard values?.isRegularFile == true,
                      values?.isSymbolicLink != true,
                      extensions.contains(url.pathExtension.lowercased()),
                      !pathsContain(url.standardizedFileURL.path, in: paths),
                      (values?.contentModificationDate ?? .distantFuture) < cutoff else { continue }
                let size = allocatedSize(of: url)
                guard size >= 10 * 1_024 * 1_024 else { continue }
                results.append(CleanupCandidate(
                    url: url,
                    displayName: url.lastPathComponent,
                    category: .oldInstallerPackage,
                    disposition: .recycle,
                    byteCount: size,
                    modifiedAt: values?.contentModificationDate,
                    risk: .review,
                    confidence: .exact,
                    reason: AppLocalizer.string("maintenance.reason.oldInstaller"),
                    selectedByDefault: false,
                    executionRoot: root
                ))
            }
        }
        return results
    }

    private func scanChildren(rule: CleanupRule, excluding paths: Set<String>) -> [CleanupCandidate] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isSymbolicLinkKey]
        guard let children = try? fileManager.contentsOfDirectory(
            at: rule.root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let cutoff = rule.minimumAgeDays.flatMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
        return children.compactMap { url in
            guard !Task.isCancelled else { return nil }
            let path = url.standardizedFileURL.path
            guard !pathsContain(path, in: paths),
                  !path.localizedCaseInsensitiveContains("com.yang.yuangui") else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isSymbolicLink != true else { return nil }
            if let cutoff, let modified = values?.contentModificationDate, modified > cutoff { return nil }
            if rule.category == .appCache, isProtectedCache(url) { return nil }

            let browser = rule.category == .appCache && isBrowserCache(url)
            let category: CleanupCategory = browser ? .browserCache : rule.category
            let risk: MaintenanceRisk = browser ? .review : rule.risk
            let selected = browser ? false : rule.selectedByDefault
            let size = allocatedSize(of: url)
            guard size > 0 else { return nil }
            return CleanupCandidate(
                url: url,
                displayName: url.lastPathComponent,
                category: category,
                disposition: rule.disposition,
                byteCount: size,
                modifiedAt: values?.contentModificationDate,
                risk: risk,
                confidence: .exact,
                reason: browser ? AppLocalizer.string("maintenance.reason.browserCache") : rule.reason,
                selectedByDefault: selected
            )
        }
    }

    private func scanOrphanedData(excluding paths: Set<String>) -> [CleanupCandidate] {
        let library = userLibraryDirectory
        let installed = installedBundleIdentifiers()
        let roots = [
            library.appendingPathComponent("Application Support"),
            library.appendingPathComponent("Preferences"),
            library.appendingPathComponent("Saved Application State"),
            library.appendingPathComponent("WebKit"),
            library.appendingPathComponent("HTTPStorages"),
            library.appendingPathComponent("Containers"),
            library.appendingPathComponent("Application Scripts")
        ]
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        var results: [CleanupCandidate] = []
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in children {
                guard !Task.isCancelled else { return results }
                let path = url.standardizedFileURL.path
                guard !pathsContain(path, in: paths),
                      let bundleID = inferredBundleIdentifier(from: url.lastPathComponent),
                      !hasInstalledOwner(bundleID, installed: installed),
                      !bundleID.hasPrefix("com.apple."),
                      bundleID != "com.yang.yuangui" else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true,
                      (values?.contentModificationDate ?? .distantFuture) < cutoff else { continue }
                let size = allocatedSize(of: url)
                guard size > 0 else { continue }
                results.append(CleanupCandidate(
                    url: url,
                    displayName: url.lastPathComponent,
                    category: .orphanedAppData,
                    disposition: .recycle,
                    byteCount: size,
                    modifiedAt: values?.contentModificationDate,
                    risk: .review,
                    confidence: .inferred,
                    reason: AppLocalizer.string("maintenance.reason.orphanedData"),
                    selectedByDefault: false
                ))
            }
        }
        return results
    }

    private func applicationRoots() -> [(url: URL, source: ApplicationSource)] {
        if let applicationRootsOverride { return applicationRootsOverride }
        return [
            (URL(fileURLWithPath: "/Applications", isDirectory: true), .systemApplications),
            (URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true), .utilities),
            (URL(fileURLWithPath: "/Applications/Setapp", isDirectory: true), .setapp),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true), .userApplications)
        ]
    }

    private var userLibraryDirectory: URL {
        userLibraryOverride ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    }

    private var homeDirectory: URL {
        homeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
    }

    private var downloadsDirectory: URL {
        downloadsDirectoryOverride ?? homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    private var desktopDirectory: URL {
        desktopDirectoryOverride ?? homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
    }

    private var projectArtifactNames: Set<String> {
        ["node_modules", ".build", "target", "build", "dist", ".next", ".venv", "Pods"]
    }

    private func isProjectArtifact(_ url: URL, boundedBy root: URL) -> Bool {
        let projectMarkers: Set<String> = [
            "Package.swift", "package.json", "Cargo.toml", "go.mod", "Podfile",
            "pyproject.toml", "requirements.txt", "build.gradle", "settings.gradle", ".git"
        ]
        var parent = url.deletingLastPathComponent()
        while parent.path.hasPrefix(root.path) {
            if projectMarkers.contains(where: { fileManager.fileExists(atPath: parent.appendingPathComponent($0).path) }) {
                return true
            }
            if parent.standardizedFileURL.path == root.standardizedFileURL.path { break }
            parent.deleteLastPathComponent()
        }
        return false
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func installedBundleIdentifiers() -> Set<String> {
        var ids: Set<String> = []
        for root in applicationRoots() {
            guard let apps = try? fileManager.contentsOfDirectory(at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for app in apps where app.pathExtension.lowercased() == "app" {
                if let id = Bundle(url: app)?.bundleIdentifier { ids.insert(id) }
                ids.formUnion(embeddedBundleIdentifiers(in: app))
            }
        }
        return ids
    }

    private func hasInstalledOwner(_ bundleID: String, installed: Set<String>) -> Bool {
        installed.contains(bundleID) || installed.contains { bundleID.hasPrefix($0 + ".") }
    }

    private func applicationMetadata(for app: URL) -> ApplicationMetadata {
        let values = try? app.resourceValues(forKeys: [.contentModificationDateKey])
        if let cached = metadataCache.value(for: app, modificationDate: values?.contentModificationDate) {
            return cached
        }
        var byteCount: Int64 = 0
        var lastUsedAt: Date?
        if let item = MDItemCreate(kCFAllocatorDefault, app.path as CFString) {
            if let size = MDItemCopyAttribute(item, "kMDItemFSSize" as CFString) as? NSNumber {
                byteCount = size.int64Value
            }
            lastUsedAt = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        if byteCount <= 0 { byteCount = allocatedSize(of: app) }
        if lastUsedAt == nil {
            lastUsedAt = try? app.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
        }
        let result = ApplicationMetadata(
            path: app.standardizedFileURL.path,
            modificationDate: values?.contentModificationDate,
            byteCount: byteCount,
            lastUsedAt: lastUsedAt,
            cachedAt: Date()
        )
        metadataCache.set(result)
        return result
    }

    private func uninstallComponents(
        app: URL,
        name: String,
        bundleID: String,
        appSize: Int64,
        includeResiduals: Bool
    ) -> [UninstallComponent] {
        var components = [UninstallComponent(
            url: app,
            kind: .application,
            byteCount: appSize,
            risk: .recommended,
            confidence: .exact,
            reason: AppLocalizer.string("maintenance.reason.selectedApp"),
            selectedByDefault: true
        )]
        guard includeResiduals, isValidBundleIdentifier(bundleID) else { return components }

        let library = userLibraryDirectory
        var identifiers: Set<String> = [bundleID]
        identifiers.formUnion(embeddedBundleIdentifiers(in: app))
        for identifier in identifiers {
            let exactPaths: [(String, UninstallComponentKind, String)] = [
                ("Application Support/\(identifier)", .applicationSupport, AppLocalizer.string("maintenance.reason.exactApplicationData")),
                ("Caches/\(identifier)", .cache, AppLocalizer.string("maintenance.reason.exactCache")),
                ("Logs/\(identifier)", .log, AppLocalizer.string("maintenance.reason.exactLog")),
                ("Preferences/\(identifier).plist", .preference, AppLocalizer.string("maintenance.reason.exactPreference")),
                ("Saved Application State/\(identifier).savedState", .savedState, AppLocalizer.string("maintenance.reason.exactSavedState")),
                ("WebKit/\(identifier)", .webData, AppLocalizer.string("maintenance.reason.exactWebData")),
                ("HTTPStorages/\(identifier)", .webData, AppLocalizer.string("maintenance.reason.exactNetworkCache")),
                ("HTTPStorages/\(identifier).binarycookies", .webData, AppLocalizer.string("maintenance.reason.exactNetworkCache")),
                ("Containers/\(identifier)", .container, AppLocalizer.string("maintenance.reason.exactContainer")),
                ("Application Scripts/\(identifier)", .applicationScript, AppLocalizer.string("maintenance.reason.exactApplicationScript")),
                ("LaunchAgents/\(identifier).plist", .launchAgent, AppLocalizer.string("maintenance.reason.exactLaunchAgent"))
            ]
            for item in exactPaths {
                let url = library.appendingPathComponent(item.0)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                components.append(component(
                    url: url,
                    kind: item.1,
                    risk: .recommended,
                    confidence: .exact,
                    reason: item.2,
                    selectedByDefault: true
                ))
            }

            let launchAgents = library.appendingPathComponent("LaunchAgents")
            if let items = try? fileManager.contentsOfDirectory(at: launchAgents, includingPropertiesForKeys: nil) {
                for url in items where url.lastPathComponent.hasPrefix(identifier + ".") && url.pathExtension == "plist" {
                    components.append(component(
                        url: url, kind: .launchAgent, risk: .recommended, confidence: .exact,
                        reason: AppLocalizer.string("maintenance.reason.boundaryLaunchAgent"), selectedByDefault: true
                    ))
                }
            }

            let groups = library.appendingPathComponent("Group Containers")
            if let items = try? fileManager.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in items where url.lastPathComponent == identifier || url.lastPathComponent.hasSuffix(".\(identifier)") {
                    components.append(component(
                        url: url, kind: .sharedContainer, risk: .protected, confidence: .shared,
                        reason: AppLocalizer.string("maintenance.reason.sharedContainer"), selectedByDefault: false
                    ))
                }
            }
        }

        let namePaths: [(String, UninstallComponentKind)] = [
            ("Application Support/\(name)", .applicationSupport),
            ("Caches/\(name)", .cache),
            ("Logs/\(name)", .log)
        ]
        if name.count >= 4 {
            for item in namePaths {
                let url = library.appendingPathComponent(item.0)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                components.append(component(
                    url: url, kind: item.1, risk: .review, confidence: .inferred,
                    reason: AppLocalizer.string("maintenance.reason.inferredByName"), selectedByDefault: false
                ))
            }
        }

        let crashRoot = library.appendingPathComponent("Application Support/CrashReporter")
        if let items = try? fileManager.contentsOfDirectory(at: crashRoot, includingPropertiesForKeys: nil), name.count >= 3 {
            let compactName = name.replacingOccurrences(of: " ", with: "")
            for url in items where url.lastPathComponent.hasPrefix(name + "_") || url.lastPathComponent.hasPrefix(compactName + "_") {
                components.append(component(
                    url: url, kind: .crashReport, risk: .review, confidence: .inferred,
                    reason: AppLocalizer.string("maintenance.reason.executableCrashReport"), selectedByDefault: false
                ))
            }
        }

        var seen: Set<String> = []
        return components.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    private func component(
        url: URL,
        kind: UninstallComponentKind,
        risk: MaintenanceRisk,
        confidence: OwnershipConfidence,
        reason: String,
        selectedByDefault: Bool
    ) -> UninstallComponent {
        UninstallComponent(
            url: url,
            kind: kind,
            byteCount: allocatedSize(of: url),
            risk: risk,
            confidence: confidence,
            reason: reason,
            selectedByDefault: selectedByDefault
        )
    }

    func embeddedBundleIdentifiers(in app: URL) -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: app.appendingPathComponent("Contents"),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var identifiers: Set<String> = []
        var scanned = 0
        for case let url as URL in enumerator {
            guard scanned < 128 else { break }
            guard url.lastPathComponent == "Info.plist", url.path.hasSuffix("/Contents/Info.plist") else { continue }
            scanned += 1
            let bundleRoot = url.deletingLastPathComponent().deletingLastPathComponent()
            guard bundleRoot != app else { continue }
            let ext = bundleRoot.pathExtension.lowercased()
            let isLoginItem = ext == "app" && bundleRoot.path.contains("/Contents/Library/LoginItems/")
            guard ext == "xpc" || ext == "appex" || isLoginItem else { continue }
            let plistID = (NSDictionary(contentsOf: url)?["CFBundleIdentifier"] as? String)
            if let id = Bundle(url: bundleRoot)?.bundleIdentifier ?? plistID,
               isValidBundleIdentifier(id),
               !id.hasPrefix("com.apple."),
               !id.hasPrefix("org.sparkle-project.") {
                identifiers.insert(id)
            }
        }
        return identifiers
    }

    private func hasSystemLevelComponents(app: URL, bundleID: String) -> Bool {
        let roots = [
            app.appendingPathComponent("Contents/Library/SystemExtensions"),
            app.appendingPathComponent("Contents/Library/LaunchServices")
        ]
        if roots.contains(where: { fileManager.fileExists(atPath: $0.path) }) { return true }
        let exactSystemPaths = [
            "/Library/LaunchDaemons/\(bundleID).plist",
            "/Library/LaunchAgents/\(bundleID).plist",
            "/Library/PrivilegedHelperTools/\(bundleID)"
        ]
        return exactSystemPaths.contains(where: fileManager.fileExists(atPath:))
    }

    private func applicationManagement(for url: URL, source: ApplicationSource) -> ApplicationManagement {
        if source == .setapp { return .setapp }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true,
           url.resolvingSymlinksInPath().path.contains("/Caskroom/") {
            return .homebrew
        }
        return .direct
    }

    func isBrowserCache(_ url: URL) -> Bool {
        let value = url.lastPathComponent.lowercased()
        return [
            "safari", "google", "chrome", "chromium", "mozilla", "firefox",
            "microsoft edge", "microsoft.edge", "thebrowser", "arc", "brave", "opera"
        ].contains { value.contains($0) }
    }

    func isProtectedCache(_ url: URL) -> Bool {
        let value = url.lastPathComponent.lowercased()
        if value.hasPrefix("com.apple.") { return true }
        return [
            "security", "keychain", "keyring", "safe storage", "trustd",
            "1password", "bitwarden", "keepass", "vscode", "visual studio code", "electron",
            "crowdstrike", "sentinel", "jamf", "kandji", "defender", "sophos", "zscaler",
            "inputmethod", "ime", "baiduinput", "sogou", "rime", "google drive", "dropbox",
            "onedrive", "box", "icloud", "vpn", "openvpn", "tailscale", "claude", "ollama",
            "comfyui", "stable diffusion", "huggingface", "llama"
        ].contains { value.contains($0) }
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let rootValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        guard rootValues?.isSymbolicLink != true else { return 0 }
        if rootValues?.isRegularFile == true {
            return Int64(rootValues?.totalFileAllocatedSize ?? rootValues?.fileAllocatedSize ?? rootValues?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var size: Int64 = 0
        var hardLinks: Set<String> = []
        for case let item as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values?.isRegularFile == true {
                let attributes = try? fileManager.attributesOfItem(atPath: item.path)
                let device = (attributes?[.systemNumber] as? NSNumber)?.int64Value
                let inode = (attributes?[.systemFileNumber] as? NSNumber)?.int64Value
                if let device, let inode, !hardLinks.insert("\(device):\(inode)").inserted { continue }
                size += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }
        return size
    }

    private func inferredBundleIdentifier(from name: String) -> String? {
        var candidate = name
        for suffix in [".binarycookies", ".savedState", ".plist"] where candidate.hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
        }
        return isValidBundleIdentifier(candidate) ? candidate : nil
    }

    private func isValidBundleIdentifier(_ value: String) -> Bool {
        BundleIdentifierValidator.isValid(value)
    }

    private func pathsContain(_ path: String, in excluded: Set<String>) -> Bool {
        excluded.contains { value in
            let root = URL(fileURLWithPath: value).standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }
    }

    private func deduplicated(_ candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }
}

final class NativeMaintenanceService: MaintenanceHandling {
    private let fileManager: FileManager
    private let validator: SafePathValidator
    private let logger: MaintenanceLogging

    init(
        fileManager: FileManager = .default,
        validator: SafePathValidator = SafePathValidator(),
        logger: MaintenanceLogging = MaintenanceLogStore()
    ) {
        self.fileManager = fileManager
        self.validator = validator
        self.logger = logger
    }

    func clean(_ candidates: [CleanupCandidate]) async -> MaintenanceOperation {
        var permanentBytes: Int64 = 0
        var trashedBytes: Int64 = 0
        var results: [MaintenanceItemResult] = []
        var skipped: [String] = []
        var errors: [String] = []

        for candidate in candidates {
            do {
                let safe = try validatorForCandidate(candidate).validate(candidate.url)
                guard candidate.scannedIdentity.stillMatches(safe, fileManager: fileManager) else {
                    let message = AppLocalizer.string("maintenance.error.changedAfterScan")
                    skipped.append("\(candidate.displayName)：\(message)")
                    results.append(itemResult(candidate, outcome: .skipped, message: message))
                    continue
                }
                if candidate.disposition == .permanent {
                    try fileManager.removeItem(at: safe)
                    permanentBytes += candidate.byteCount
                    results.append(itemResult(candidate, outcome: .deleted))
                } else {
                    try await recycle([safe])
                    trashedBytes += candidate.byteCount
                    results.append(itemResult(candidate, outcome: .trashed))
                }
            } catch {
                let message = error.localizedDescription
                errors.append("\(candidate.displayName)：\(message)")
                results.append(itemResult(candidate, outcome: .failed, message: message))
            }
        }

        let operation = MaintenanceOperation(
            kind: .cleanup,
            title: AppLocalizer.string("maintenance.operation.cleanup"),
            itemCount: results.filter { $0.outcome == .deleted || $0.outcome == .trashed }.count,
            reclaimedBytes: permanentBytes + trashedBytes,
            skipped: skipped,
            errors: errors,
            permanentlyDeletedBytes: permanentBytes,
            trashedBytes: trashedBytes,
            results: results
        )
        try? logger.append(operation)
        return operation
    }

    func uninstall(_ applications: [ApplicationCandidate]) async -> MaintenanceOperation {
        var completedApps = 0
        var trashedBytes: Int64 = 0
        var skipped: [String] = []
        var errors: [String] = []
        var results: [MaintenanceItemResult] = []

        for app in applications {
            guard !app.removalBlocked else {
                let message = app.warnings.first ?? AppLocalizer.string("maintenance.warning.officialUninstaller")
                skipped.append("\(app.name)：\(message)")
                results.append(applicationResult(app, outcome: .skipped, message: message))
                continue
            }
            guard BundleIdentifierValidator.isValid(app.bundleIdentifier),
                  !app.bundleIdentifier.hasPrefix("com.apple."),
                  app.bundleIdentifier != "com.yang.yuangui" else {
                let message = AppLocalizer.string("maintenance.error.invalidBundleID")
                skipped.append("\(app.name)：\(message)")
                results.append(applicationResult(app, outcome: .skipped, message: message))
                continue
            }
            guard isApplicationStillSafe(app) else {
                let message = AppLocalizer.string("maintenance.error.appChangedAfterScan")
                skipped.append("\(app.name)：\(message)")
                results.append(applicationResult(app, outcome: .skipped, message: message))
                continue
            }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
            if !running.isEmpty {
                let message = AppLocalizer.string("maintenance.error.appRunning")
                skipped.append("\(app.name)：\(message)")
                results.append(applicationResult(app, outcome: .skipped, message: message))
                continue
            }

            let siblingExists = hasBundleIDSibling(for: app)
            var appBodyTrashed = false
            for component in app.components {
                if component.risk == .protected || (siblingExists && component.kind != .application) {
                    let message = component.risk == .protected
                        ? AppLocalizer.string("maintenance.error.sharedOrProtectedComponent")
                        : AppLocalizer.string("maintenance.error.sharedBundleID")
                    skipped.append("\(app.name) · \(component.kind.title)：\(message)")
                    results.append(MaintenanceItemResult(
                        path: component.url.path,
                        displayName: component.url.lastPathComponent,
                        outcome: .skipped,
                        byteCount: component.byteCount,
                        message: message
                    ))
                    continue
                }
                do {
                    let safe: URL
                    if component.kind == .application {
                        guard component.url.standardizedFileURL.path == app.url.standardizedFileURL.path,
                              component.scannedIdentity.stillMatches(component.url, fileManager: fileManager) else {
                            throw MaintenanceExecutionError.changedSinceScan
                        }
                        safe = component.url
                    } else {
                        safe = try validator.validate(component.url)
                        guard component.scannedIdentity.stillMatches(safe, fileManager: fileManager) else {
                            throw MaintenanceExecutionError.changedSinceScan
                        }
                        if component.kind == .launchAgent {
                            bootoutUserLaunchAgent(safe)
                        }
                    }
                    try await recycle([safe])
                    trashedBytes += component.byteCount
                    appBodyTrashed = appBodyTrashed || component.kind == .application
                    results.append(MaintenanceItemResult(
                        path: safe.path,
                        displayName: safe.lastPathComponent,
                        outcome: .trashed,
                        byteCount: component.byteCount
                    ))
                } catch {
                    let message = error.localizedDescription
                    errors.append("\(app.name) · \(component.kind.title)：\(message)")
                    results.append(MaintenanceItemResult(
                        path: component.url.path,
                        displayName: component.url.lastPathComponent,
                        outcome: .failed,
                        byteCount: component.byteCount,
                        message: message
                    ))
                }
            }
            if appBodyTrashed { completedApps += 1 }
        }

        let operation = MaintenanceOperation(
            kind: .uninstall,
            title: AppLocalizer.string("maintenance.operation.uninstall"),
            itemCount: completedApps,
            reclaimedBytes: trashedBytes,
            skipped: skipped,
            errors: errors,
            permanentlyDeletedBytes: 0,
            trashedBytes: trashedBytes,
            results: results
        )
        try? logger.append(operation)
        return operation
    }

    private func itemResult(
        _ candidate: CleanupCandidate,
        outcome: MaintenanceItemResult.Outcome,
        message: String? = nil
    ) -> MaintenanceItemResult {
        MaintenanceItemResult(
            path: candidate.url.path,
            displayName: candidate.displayName,
            outcome: outcome,
            byteCount: candidate.byteCount,
            message: message
        )
    }

    private func validatorForCandidate(_ candidate: CleanupCandidate) -> SafePathValidator {
        guard let root = candidate.executionRoot?.standardizedFileURL.resolvingSymlinksInPath() else {
            return validator
        }
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard root.path != home,
              root.path.hasPrefix(home + "/"),
              !((try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true) else {
            return validator
        }
        return SafePathValidator(allowedRoots: validator.allowedRoots + [root])
    }

    private func applicationResult(
        _ application: ApplicationCandidate,
        outcome: MaintenanceItemResult.Outcome,
        message: String
    ) -> MaintenanceItemResult {
        MaintenanceItemResult(
            path: application.url.path,
            displayName: application.name,
            outcome: outcome,
            byteCount: application.byteCount,
            message: message
        )
    }

    private func hasBundleIDSibling(for candidate: ApplicationCandidate) -> Bool {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Setapp", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            guard let applications = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            if applications.contains(where: {
                $0.pathExtension.lowercased() == "app"
                    && $0.standardizedFileURL.path != candidate.url.standardizedFileURL.path
                    && Bundle(url: $0)?.bundleIdentifier == candidate.bundleIdentifier
            }) { return true }
        }
        return false
    }

    private func isApplicationStillSafe(_ candidate: ApplicationCandidate) -> Bool {
        let url = candidate.url.standardizedFileURL
        let allowedParents = [
            "/Applications",
            "/Applications/Utilities",
            "/Applications/Setapp",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).path
        ]
        guard url.pathExtension.lowercased() == "app",
              allowedParents.contains(url.deletingLastPathComponent().path),
              url.path != Bundle.main.bundleURL.standardizedFileURL.path,
              fileManager.fileExists(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              Bundle(url: url)?.bundleIdentifier == candidate.bundleIdentifier else { return false }
        return true
    }

    private func bootoutUserLaunchAgent(_ url: URL) {
        guard url.pathExtension == "plist",
              url.deletingLastPathComponent().path == fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true).path else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func recycle(_ urls: [URL]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle(urls) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}

private enum MaintenanceExecutionError: LocalizedError {
    case changedSinceScan

    var errorDescription: String? {
        AppLocalizer.string("maintenance.error.changedAfterScan")
    }
}
