import AppKit
import Foundation

protocol CleanupScanning {
    func scan(excluding paths: Set<String>) async -> [CleanupCandidate]
    func scanApplications() async -> [ApplicationCandidate]
}

protocol MaintenanceHandling {
    func clean(_ candidates: [CleanupCandidate]) async -> MaintenanceOperation
    func uninstall(_ applications: [ApplicationCandidate]) async -> MaintenanceOperation
}

struct CleanupScanner: CleanupScanning {
    private let fileManager: FileManager
    private let calendar: Calendar

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func scan(excluding paths: Set<String>) async -> [CleanupCandidate] {
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        var candidates: [CleanupCandidate] = []
        candidates += scanChildren(
            of: library.appendingPathComponent("Caches"),
            category: .appCache, disposition: .recycle, olderThanDays: nil, excluding: paths
        )
        candidates += scanChildren(
            of: library.appendingPathComponent("Logs"),
            category: .oldLog, disposition: .permanent, olderThanDays: 7, excluding: paths
        )
        candidates += scanChildren(
            of: fileManager.temporaryDirectory,
            category: .temporary, disposition: .permanent, olderThanDays: 7, excluding: paths
        )
        candidates += scanChildren(
            of: library.appendingPathComponent("Developer/Xcode/DerivedData"),
            category: .developerCache, disposition: .permanent, olderThanDays: nil, excluding: paths
        )
        candidates += scanOrphanedData(library: library, excluding: paths)
        return deduplicated(candidates).sorted { $0.byteCount > $1.byteCount }
    }

    func scanApplications() async -> [ApplicationCandidate] {
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        let residualRoots = residualSearchRoots()
        var results: [ApplicationCandidate] = []
        for root in roots {
            guard let apps = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentAccessDateKey], options: [.skipsHiddenFiles]) else { continue }
            for app in apps where app.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: app), let bundleID = bundle.bundleIdentifier,
                      !bundleID.hasPrefix("com.apple."), bundleID != "com.yang.yuangui" else { continue }
                let values = try? app.resourceValues(forKeys: [.contentAccessDateKey])
                let residuals = residualRoots.flatMap { root -> [URL] in
                    commonResidualNames(for: bundleID).map { root.appendingPathComponent($0) }
                        .filter { fileManager.fileExists(atPath: $0.path) }
                }
                results.append(ApplicationCandidate(
                    url: app,
                    name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? app.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: bundleID,
                    byteCount: allocatedSize(of: app),
                    lastUsedAt: values?.contentAccessDate,
                    residuals: residuals
                ))
            }
        }
        return results.sorted { $0.byteCount > $1.byteCount }
    }

    private func scanChildren(
        of root: URL,
        category: CleanupCategory,
        disposition: CleanupDisposition,
        olderThanDays: Int?,
        excluding paths: Set<String>
    ) -> [CleanupCandidate] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isSymbolicLinkKey]
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = olderThanDays.flatMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
        return children.compactMap { url in
            guard !paths.contains(url.path), !url.path.localizedCaseInsensitiveContains("com.yang.yuangui") else { return nil }
            if root.lastPathComponent == "Caches", isProtectedCache(url) { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isSymbolicLink != true else { return nil }
            if let cutoff, let modified = values?.contentModificationDate, modified > cutoff { return nil }
            let resolvedCategory: CleanupCategory = category == .appCache && isBrowserCache(url) ? .browserCache : category
            let size = allocatedSize(of: url)
            guard size > 0 else { return nil }
            return CleanupCandidate(
                url: url,
                displayName: url.lastPathComponent,
                category: resolvedCategory,
                disposition: disposition,
                byteCount: size,
                modifiedAt: values?.contentModificationDate
            )
        }
    }

    private func scanOrphanedData(library: URL, excluding paths: Set<String>) -> [CleanupCandidate] {
        let installed = installedBundleIdentifiers()
        let roots = residualSearchRoots().filter { !$0.path.hasSuffix("Caches") && !$0.path.hasSuffix("Logs") }
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        var results: [CleanupCandidate] = []
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for url in children {
                guard !paths.contains(url.path), let bundleID = inferredBundleIdentifier(from: url.lastPathComponent),
                      !installed.contains(bundleID), !bundleID.hasPrefix("com.apple."), bundleID != "com.yang.yuangui" else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true, (values?.contentModificationDate ?? .distantFuture) < cutoff else { continue }
                let size = allocatedSize(of: url)
                guard size > 0 else { continue }
                results.append(CleanupCandidate(
                    url: url, displayName: url.lastPathComponent, category: .orphanedAppData,
                    disposition: .recycle, byteCount: size, modifiedAt: values?.contentModificationDate
                ))
            }
        }
        return results
    }

    private func installedBundleIdentifiers() -> Set<String> {
        let roots = [URL(fileURLWithPath: "/Applications"), fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var ids: Set<String> = []
        for root in roots {
            guard let apps = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for app in apps where app.pathExtension.lowercased() == "app" {
                if let id = Bundle(url: app)?.bundleIdentifier { ids.insert(id) }
            }
        }
        return ids
    }

    private func residualSearchRoots() -> [URL] {
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return ["Application Support", "Caches", "Logs", "Preferences", "Saved Application State", "WebKit"].map {
            library.appendingPathComponent($0)
        }
    }

    private func commonResidualNames(for bundleID: String) -> [String] {
        [bundleID, "\(bundleID).plist", "\(bundleID).savedState"]
    }

    private func inferredBundleIdentifier(from name: String) -> String? {
        var candidate = name
        for suffix in [".savedState", ".plist"] where candidate.hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
        }
        let parts = candidate.split(separator: ".")
        guard parts.count >= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) else { return nil }
        return candidate
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
            "1password", "bitwarden", "keepass", "vscode", "visual studio code", "electron"
        ].contains { value.contains($0) }
    }

    private func allocatedSize(of url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        var size: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values?.isRegularFile == true { size += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0) }
        }
        return size
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

    init(fileManager: FileManager = .default, validator: SafePathValidator = SafePathValidator(), logger: MaintenanceLogging = MaintenanceLogStore()) {
        self.fileManager = fileManager
        self.validator = validator
        self.logger = logger
    }

    func clean(_ candidates: [CleanupCandidate]) async -> MaintenanceOperation {
        var reclaimed: Int64 = 0
        var completed = 0
        var skipped: [String] = []
        var errors: [String] = []
        let recyclable = candidates.filter { $0.disposition == .recycle }
        for candidate in candidates where candidate.disposition == .permanent {
            do {
                let safe = try validator.validate(candidate.url)
                guard fileManager.fileExists(atPath: safe.path) else { skipped.append("\(candidate.displayName)：已不存在"); continue }
                try fileManager.removeItem(at: safe)
                reclaimed += candidate.byteCount; completed += 1
            } catch { errors.append("\(candidate.displayName)：\(error.localizedDescription)") }
        }
        if !recyclable.isEmpty {
            var safeURLs: [URL] = []
            for candidate in recyclable {
                do { safeURLs.append(try validator.validate(candidate.url)) }
                catch { errors.append("\(candidate.displayName)：\(error.localizedDescription)") }
            }
            if !safeURLs.isEmpty {
                do {
                    try await recycle(safeURLs)
                    let safePaths = Set(safeURLs.map(\.path))
                    for item in recyclable where safePaths.contains(item.url.resolvingSymlinksInPath().path) {
                        reclaimed += item.byteCount; completed += 1
                    }
                } catch { errors.append("移入废纸篓失败：\(error.localizedDescription)") }
            }
        }
        let operation = MaintenanceOperation(kind: .cleanup, title: "空间清理", itemCount: completed, reclaimedBytes: reclaimed, skipped: skipped, errors: errors)
        try? logger.append(operation)
        return operation
    }

    func uninstall(_ applications: [ApplicationCandidate]) async -> MaintenanceOperation {
        var completed = 0
        var reclaimed: Int64 = 0
        var skipped: [String] = []
        var errors: [String] = []
        for app in applications {
            guard !app.bundleIdentifier.hasPrefix("com.apple."), app.bundleIdentifier != "com.yang.yuangui" else {
                skipped.append("\(app.name)：受保护应用"); continue
            }
            guard isApplicationStillSafe(app) else {
                skipped.append("\(app.name)：应用位置或身份已变化，请重新扫描"); continue
            }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
            if !running.isEmpty {
                running.forEach { _ = $0.terminate() }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty {
                    skipped.append("\(app.name)：应用仍在运行"); continue
                }
            }
            do {
                var urls = [app.url]
                for residual in app.residuals {
                    if let safe = try? validator.validate(residual) { urls.append(safe) }
                }
                try await recycle(urls)
                completed += 1
                reclaimed += app.byteCount
            } catch { errors.append("\(app.name)：\(error.localizedDescription)") }
        }
        let operation = MaintenanceOperation(kind: .uninstall, title: "软件卸载", itemCount: completed, reclaimedBytes: reclaimed, skipped: skipped, errors: errors)
        try? logger.append(operation)
        return operation
    }

    private func isApplicationStillSafe(_ candidate: ApplicationCandidate) -> Bool {
        let url = candidate.url.standardizedFileURL
        let allowedParents = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        ]
        guard url.pathExtension.lowercased() == "app",
              allowedParents.contains(url.deletingLastPathComponent().path),
              url.path != Bundle.main.bundleURL.standardizedFileURL.path,
              fileManager.fileExists(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              Bundle(url: url)?.bundleIdentifier == candidate.bundleIdentifier else { return false }
        return true
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
