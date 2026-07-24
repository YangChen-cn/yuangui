import CryptoKit
import Foundation

actor DiaryExportService {
    private let layout: DiaryStorageLayout
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let restoreInstallationValidator: (@Sendable (URL) throws -> Void)?

    init(
        layout: DiaryStorageLayout,
        fileManager: FileManager = .default,
        restoreInstallationValidator: (@Sendable (URL) throws -> Void)? = nil
    ) {
        self.layout = layout
        self.fileManager = fileManager
        self.restoreInstallationValidator = restoreInstallationValidator
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func exportMarkdown(entries: [DiaryEntry], to destination: URL) throws -> URL {
        let work = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: work) }
        let markdownURL = work.appendingPathComponent(destination.lastPathComponent)
        let resourceName = "\(destination.deletingPathExtension().lastPathComponent)-attachments"
        let resourceURL = work.appendingPathComponent(resourceName, isDirectory: true)
        try fileManager.createDirectory(at: resourceURL, withIntermediateDirectories: true)
        var markdown = "# 手帐本\n\n"
        markdown += "导出时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        markdown += "共 \(entries.count) 条日记\n\n---\n\n"
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        for entry in entries.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            markdown += "## \(entry.title ?? entry.displayTitle)\n\n"
            markdown += "**日期：** \(formatter.string(from: entry.occurredAt))"
            if let mood = entry.mood { markdown += "　　**心情：** \(mood.emoji) \(mood.title)" }
            markdown += "\n\n"
            if !entry.tags.isEmpty { markdown += "**标签：** \(entry.tags.joined(separator: "、"))\n\n" }
            if let location = entry.locationName, !location.isEmpty { markdown += "**地点：** \(location)\n\n" }
            if let weather = entry.weather { markdown += "**天气：** \(weather.icon) \(weather.condition)，\(Int(weather.temperature.rounded()))°C\n\n" }
            if let music = entry.music { markdown += "**音乐：** \(music.title) — \(music.artist)\n\n" }
            markdown += entry.body + "\n\n"
            for attachment in entry.attachments {
                let source = layout.originalsURL.appendingPathComponent(attachment.filename)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let exportedName = "\(entry.id.uuidString.lowercased())-\(attachment.filename)"
                try fileManager.copyItem(at: source, to: resourceURL.appendingPathComponent(exportedName))
                markdown += "![\(attachment.originalFilename)](\(resourceName)/\(exportedName))\n\n"
            }
            markdown += "---\n\n"
        }
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        try replaceItem(at: destination, with: markdownURL)
        let finalResources = destination.deletingLastPathComponent().appendingPathComponent(resourceName, isDirectory: true)
        if fileManager.fileExists(atPath: finalResources.path) { try fileManager.removeItem(at: finalResources) }
        if !((try? fileManager.contentsOfDirectory(atPath: resourceURL.path).isEmpty) ?? true) {
            try fileManager.moveItem(at: resourceURL, to: finalResources)
        }
        return destination
    }

    func exportJSON(entries: [DiaryEntry], to destination: URL) throws -> URL {
        let document = DiaryExportDocument(formatVersion: 1, exportedAt: Date(), entries: entries)
        let staged = try stagedURL(for: destination)
        defer { try? fileManager.removeItem(at: staged) }
        try encoder.encode(document).write(to: staged, options: .atomic)
        try installStagedItem(staged, at: destination)
        return destination
    }

    func exportZIP(entries: [DiaryEntry], to destination: URL) throws -> URL {
        let work = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: work) }
        let entriesURL = work.appendingPathComponent("Entries", isDirectory: true)
        let originalsURL = work.appendingPathComponent("Attachments/Originals", isDirectory: true)
        let thumbnailsURL = work.appendingPathComponent("Attachments/Thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: entriesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: originalsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        for entry in entries {
            try encoder.encode(DiaryFileEnvelope(entry: entry)).write(
                to: entriesURL.appendingPathComponent("\(entry.id.uuidString.lowercased()).diaryentry"),
                options: .atomic
            )
            try copyAttachments(for: entry, originalsURL: originalsURL, thumbnailsURL: thumbnailsURL)
        }
        try writeManifest(in: work, entryCount: entries.count)
        try zipDirectory(work, to: destination)
        return destination
    }

    func backup(to destination: URL) throws -> URL {
        let work = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: work) }
        for name in ["Entries", "Attachments"] {
            let source = layout.rootURL.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: work.appendingPathComponent(name, isDirectory: true))
            }
        }
        let entryCount = (try? fileManager.contentsOfDirectory(at: work.appendingPathComponent("Entries"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "diaryentry" }.count) ?? 0
        try writeManifest(in: work, entryCount: entryCount)
        try zipDirectory(work, to: destination)
        return destination
    }

    func restore(from backupURL: URL) throws -> DiaryLoadReport {
        let listing = try archiveListing(backupURL)
        try validateArchivePaths(listing)
        try validateArchiveContainsNoSymbolicLinks(backupURL)
        let extracted = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: extracted) }
        try runProcess("/usr/bin/unzip", arguments: ["-q", backupURL.path, "-d", extracted.path])
        try validateExtractedTree(extracted)
        let report = try validateCandidate(extracted)

        let parent = layout.rootURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let rollback = parent.appendingPathComponent("Diary-Rollback-\(UUID().uuidString)", isDirectory: true)
        let hadExisting = fileManager.fileExists(atPath: layout.rootURL.path)
        do {
            if hadExisting { try fileManager.moveItem(at: layout.rootURL, to: rollback) }
            try fileManager.createDirectory(at: layout.rootURL, withIntermediateDirectories: true)
            for name in ["Entries", "Attachments"] {
                let source = extracted.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: layout.rootURL.appendingPathComponent(name, isDirectory: true))
                }
            }
            try restoreInstallationValidator?(layout.rootURL)
            _ = try validateInstalledData()
            if hadExisting { try fileManager.removeItem(at: rollback) }
            return report
        } catch {
            try? fileManager.removeItem(at: layout.rootURL)
            if hadExisting { try? fileManager.moveItem(at: rollback, to: layout.rootURL) }
            throw DiaryExportError.restoreFailed(error.localizedDescription)
        }
    }

    private func writeManifest(in root: URL, entryCount: Int) throws {
        let files = try regularFiles(in: root)
            .filter { $0.lastPathComponent != "manifest.json" }
            .map { url -> DiaryBackupManifest.FileRecord in
                let data = try Data(contentsOf: url)
                return DiaryBackupManifest.FileRecord(
                    path: relativePath(of: url, under: root),
                    byteCount: data.count,
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                )
            }
            .sorted { $0.path < $1.path }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let manifest = DiaryBackupManifest(formatVersion: 1, appVersion: version, createdAt: Date(), entryCount: entryCount, files: files)
        try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func validateCandidate(_ root: URL) throws -> DiaryLoadReport {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifest = try decoder.decode(DiaryBackupManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.formatVersion == 1 else { throw DiaryExportError.unsupportedBackupVersion }
        let manifestPaths = manifest.files.map(\.path)
        guard Set(manifestPaths).count == manifestPaths.count else { throw DiaryExportError.duplicateArchivePath }
        for record in manifest.files {
            let url = try validatedURL(for: record.path, under: root)
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard data.count == record.byteCount, digest == record.sha256 else {
                throw DiaryExportError.checksumMismatch(record.path)
            }
        }
        let actualPaths = try Set(regularFiles(in: root)
            .filter { $0.lastPathComponent != "manifest.json" }
            .map { relativePath(of: $0, under: root) })
        guard actualPaths == Set(manifestPaths) else { throw DiaryExportError.manifestContentsMismatch }
        let entriesURL = root.appendingPathComponent("Entries", isDirectory: true)
        let files = (try? fileManager.contentsOfDirectory(at: entriesURL, includingPropertiesForKeys: nil)) ?? []
        var entries: [DiaryEntry] = []
        for file in files where file.pathExtension == "diaryentry" {
            let data = try Data(contentsOf: file)
            let entry: DiaryEntry
            if let envelope = try? decoder.decode(DiaryFileEnvelope.self, from: data) {
                guard envelope.formatVersion <= DiaryFileEnvelope.currentFormatVersion else {
                    throw DiaryExportError.invalidEntry(file.lastPathComponent)
                }
                entry = envelope.entry
            } else {
                entry = try decoder.decode(DiaryEntry.self, from: data)
            }
            for attachment in entry.attachments {
                try validateAttachmentFilename(attachment.filename)
                let original = try validatedURL(for: "Attachments/Originals/\(attachment.filename)", under: root)
                guard fileManager.fileExists(atPath: original.path) else {
                    throw DiaryExportError.missingAttachment(attachment.filename)
                }
            }
            entries.append(entry)
        }
        guard entries.count == manifest.entryCount else { throw DiaryExportError.entryCountMismatch }
        return DiaryLoadReport(entries: entries, recoveredFiles: [])
    }

    private func validateInstalledData() throws -> DiaryLoadReport {
        let temp = try makeWorkDirectory()
        defer { try? fileManager.removeItem(at: temp) }
        for name in ["manifest.json", "Entries", "Attachments"] {
            let source = name == "manifest.json" ? nil : layout.rootURL.appendingPathComponent(name)
            if let source, fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: temp.appendingPathComponent(name))
            }
        }
        let entries = (try? fileManager.contentsOfDirectory(at: layout.entriesURL, includingPropertiesForKeys: nil)) ?? []
        try writeManifest(in: temp, entryCount: entries.filter { $0.pathExtension == "diaryentry" }.count)
        return try validateCandidate(temp)
    }

    private func validateArchivePaths(_ paths: [String]) throws {
        guard Set(paths).count == paths.count else { throw DiaryExportError.duplicateArchivePath }
        for path in paths {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            let topLevel = components.first.map(String.init) ?? ""
            let isAllowed = path == "manifest.json" || topLevel == "Entries" || topLevel == "Attachments"
            guard isAllowed,
                  !path.hasPrefix("/"),
                  !components.contains(".."),
                  !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw DiaryExportError.unsafeArchivePath(path)
            }
        }
    }

    private func validateArchiveContainsNoSymbolicLinks(_ url: URL) throws {
        let output = try processOutput("/usr/bin/zipinfo", arguments: ["-l", url.path])
        for line in output.split(separator: "\n") {
            if String(line).trimmingCharacters(in: .whitespaces).first == "l" {
                throw DiaryExportError.unsafeArchivePath(String(line))
            }
        }
    }

    private func validateExtractedTree(_ root: URL) throws {
        for url in try regularFilesAndDirectories(in: root) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw DiaryExportError.unsafeArchivePath(url.lastPathComponent) }
            let standardized = url.standardizedFileURL.path
            guard standardized == root.standardizedFileURL.path || standardized.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw DiaryExportError.unsafeArchivePath(url.path)
            }
        }
    }

    private func archiveListing(_ url: URL) throws -> [String] {
        try processOutput("/usr/bin/unzip", arguments: ["-Z1", url.path])
            .split(separator: "\n")
            .map(String.init)
    }

    private func zipDirectory(_ source: URL, to destination: URL) throws {
        let staged = try stagedURL(for: destination, pathExtension: "zip")
        defer { try? fileManager.removeItem(at: staged) }
        let contents = try fileManager.contentsOfDirectory(atPath: source.path).sorted()
        guard !contents.isEmpty else { throw DiaryExportError.zipFailed }
        try runProcess("/usr/bin/zip", arguments: ["-q", "-r", staged.path] + contents, currentDirectory: source)
        try installStagedItem(staged, at: destination)
    }

    private func runProcess(_ executable: String, arguments: [String], currentDirectory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DiaryExportError.processFailed(executable) }
    }

    private func processOutput(_ executable: String, arguments: [String]) throws -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DiaryExportError.invalidArchive }
        return String(decoding: data, as: UTF8.self)
    }

    private func copyAttachments(for entry: DiaryEntry, originalsURL: URL, thumbnailsURL: URL) throws {
        for attachment in entry.attachments {
            let original = layout.originalsURL.appendingPathComponent(attachment.filename)
            if fileManager.fileExists(atPath: original.path) {
                try fileManager.copyItem(at: original, to: originalsURL.appendingPathComponent(attachment.filename))
            }
            let thumbnail = layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename)
            if fileManager.fileExists(atPath: thumbnail.path) {
                try fileManager.copyItem(at: thumbnail, to: thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename))
            }
        }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        let staged = try stagedURL(for: destination)
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: source, to: staged)
        try installStagedItem(staged, at: destination)
    }

    private func stagedURL(for destination: URL, pathExtension: String? = nil) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        var name = ".\(destination.deletingPathExtension().lastPathComponent)-\(UUID().uuidString)"
        if let pathExtension {
            name += ".\(pathExtension)"
        } else if !destination.pathExtension.isEmpty {
            name += ".\(destination.pathExtension)"
        }
        return parent.appendingPathComponent(name)
    }

    private func installStagedItem(_ staged: URL, at destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    private func makeWorkDirectory() throws -> URL {
        try fileManager.createDirectory(at: layout.temporaryURL, withIntermediateDirectories: true)
        let url = layout.temporaryURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func regularFiles(in root: URL) throws -> [URL] {
        try regularFilesAndDirectories(in: root).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func regularFilesAndDirectories(in root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private func validatedURL(for relativePath: String, under root: URL) throws -> URL {
        try validateArchivePaths([relativePath])
        let rootPath = root.standardizedFileURL.path
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootPath + "/") else {
            throw DiaryExportError.unsafeArchivePath(relativePath)
        }
        return url
    }

    private func validateAttachmentFilename(_ filename: String) throws {
        let allowedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"])
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        let stem = (filename as NSString).deletingPathExtension
        guard filename == (filename as NSString).lastPathComponent,
              !filename.contains(".."),
              !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              allowedExtensions.contains(pathExtension),
              UUID(uuidString: stem) != nil else {
            throw DiaryExportError.unsafeArchivePath(filename)
        }
    }
}

enum DiaryExportError: LocalizedError, Sendable {
    case zipFailed
    case processFailed(String)
    case invalidArchive
    case unsafeArchivePath(String)
    case duplicateArchivePath
    case unsupportedBackupVersion
    case checksumMismatch(String)
    case manifestContentsMismatch
    case invalidEntry(String)
    case missingAttachment(String)
    case entryCountMismatch
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .zipFailed: "ZIP 创建失败"
        case .processFailed(let process): "外部工具执行失败：\(process)"
        case .invalidArchive: "备份文件不是有效 ZIP"
        case .unsafeArchivePath(let path): "备份包含不安全路径：\(path)"
        case .duplicateArchivePath: "备份包含重复路径"
        case .unsupportedBackupVersion: "备份格式版本不受支持"
        case .checksumMismatch(let path): "备份文件校验失败：\(path)"
        case .manifestContentsMismatch: "备份文件与清单内容不一致"
        case .invalidEntry(let name): "日记文件无法读取：\(name)"
        case .missingAttachment(let name): "备份缺少附件：\(name)"
        case .entryCountMismatch: "备份中的日记数量与清单不一致"
        case .restoreFailed(let message): "恢复失败，已回滚：\(message)"
        }
    }
}
