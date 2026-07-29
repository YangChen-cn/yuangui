import Foundation

actor DiaryRepository {
    private let layout: DiaryStorageLayout
    private let fileManager: FileManager
    private let beforeBatchSave: (@Sendable () async -> Void)?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        layout: DiaryStorageLayout,
        fileManager: FileManager = .default,
        beforeBatchSave: (@Sendable () async -> Void)? = nil
    ) {
        self.layout = layout
        self.fileManager = fileManager
        self.beforeBatchSave = beforeBatchSave
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    init(baseURL: URL) {
        self.init(layout: DiaryStorageLayout(rootURL: baseURL))
    }

    func save(_ entry: DiaryEntry) throws {
        try prepareDirectories()
        try write(entry)
        try removeLegacyDuplicates(for: [entry.id])
    }

    func save(_ entries: [DiaryEntry]) async -> DiarySaveReport {
        await beforeBatchSave?()
        var savedIDs = Set<UUID>()
        var failures: [DiaryWriteFailure] = []

        do {
            try prepareDirectories()
        } catch {
            return DiarySaveReport(
                savedIDs: [],
                failures: entries.map { DiaryWriteFailure(entryID: $0.id, message: error.localizedDescription) }
            )
        }

        for entry in entries {
            do {
                try write(entry)
                savedIDs.insert(entry.id)
            } catch {
                failures.append(DiaryWriteFailure(entryID: entry.id, message: error.localizedDescription))
            }
        }

        do {
            try removeLegacyDuplicates(for: savedIDs)
        } catch {
            let cleanupIDs = savedIDs
            savedIDs.removeAll()
            failures.append(contentsOf: cleanupIDs.map {
                DiaryWriteFailure(entryID: $0, message: error.localizedDescription)
            })
        }

        return DiarySaveReport(savedIDs: savedIDs, failures: failures)
    }

    func loadAll() throws -> DiaryLoadReport {
        try prepareDirectories()
        let files = try fileManager.contentsOfDirectory(at: layout.entriesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "diaryentry" }
        var entries: [DiaryEntry] = []
        var recovered: [URL] = []

        for file in files {
            do {
                entries.append(try decodeEntry(at: file))
            } catch {
                let destination = uniqueRecoveryURL(for: file)
                try fileManager.moveItem(at: file, to: destination)
                recovered.append(destination)
            }
        }
        return DiaryLoadReport(entries: entries, recoveredFiles: recovered)
    }

    func load(id: UUID) throws -> DiaryEntry? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decodeEntry(at: url)
    }

    func moveToRecentlyDeleted(_ entry: DiaryEntry) throws -> DiaryDeletedItem {
        try prepareDirectories()
        let itemURL = layout.recentlyDeletedURL.appendingPathComponent(entry.id.uuidString.lowercased(), isDirectory: true)
        guard !fileManager.fileExists(atPath: itemURL.path) else {
            throw DiaryRepositoryError.recentlyDeletedItemExists(entry.id)
        }
        try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)
        let originals = itemURL.appendingPathComponent("Originals", isDirectory: true)
        let thumbnails = itemURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: originals, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnails, withIntermediateDirectories: true)

        let deleted = DiaryDeletedItem(id: entry.id, entry: entry, deletedAt: Date())
        do {
            try encoder.encode(deleted).write(to: itemURL.appendingPathComponent("deleted.json"), options: .atomic)
            for attachment in entry.attachments {
                try validateAttachmentFilename(attachment.filename)
                try moveIfPresent(from: layout.originalsURL.appendingPathComponent(attachment.filename), to: originals.appendingPathComponent(attachment.filename))
                try moveIfPresent(from: layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename), to: thumbnails.appendingPathComponent(attachment.thumbnailFilename))
            }
            let entryURL = try existingEntryURL(for: entry.id)
            if let entryURL {
                try fileManager.moveItem(at: entryURL, to: itemURL.appendingPathComponent(entryURL.lastPathComponent))
            }
            return deleted
        } catch {
            try? rollbackDeletedItem(at: itemURL, entry: entry)
            throw error
        }
    }

    func recentlyDeleted() throws -> [DiaryDeletedItem] {
        try prepareDirectories()
        let directories = try fileManager.contentsOfDirectory(at: layout.recentlyDeletedURL, includingPropertiesForKeys: [.isDirectoryKey])
        return directories.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("deleted.json")) else { return nil }
            return try? decoder.decode(DiaryDeletedItem.self, from: data)
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    func restoreDeleted(id: UUID) throws -> DiaryEntry {
        try prepareDirectories()
        let itemURL = layout.recentlyDeletedURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let data = try Data(contentsOf: itemURL.appendingPathComponent("deleted.json"))
        let deleted = try decoder.decode(DiaryDeletedItem.self, from: data)
        guard try existingEntryURL(for: id) == nil else {
            throw DiaryRepositoryError.destinationExists(id.uuidString)
        }
        var copiedURLs: [URL] = []
        do {
            for attachment in deleted.entry.attachments {
                try validateAttachmentFilename(attachment.filename)
                let original = layout.originalsURL.appendingPathComponent(attachment.filename)
                let thumbnail = layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename)
                if try copyIfPresent(from: itemURL.appendingPathComponent("Originals/\(attachment.filename)"), to: original) {
                    copiedURLs.append(original)
                }
                if try copyIfPresent(from: itemURL.appendingPathComponent("Thumbnails/\(attachment.thumbnailFilename)"), to: thumbnail) {
                    copiedURLs.append(thumbnail)
                }
            }
            try save(deleted.entry)
            try fileManager.removeItem(at: itemURL)
            return deleted.entry
        } catch {
            try? fileManager.removeItem(at: fileURL(for: id))
            for url in copiedURLs { try? fileManager.removeItem(at: url) }
            throw error
        }
    }

    func permanentlyDelete(id: UUID) throws {
        let itemURL = layout.recentlyDeletedURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        guard fileManager.fileExists(atPath: itemURL.path) else {
            throw DiaryRepositoryError.entryNotFound(id)
        }
        try fileManager.removeItem(at: itemURL)
    }

    func purgeRecentlyDeleted(olderThan cutoff: Date) throws {
        for item in try recentlyDeleted() where item.deletedAt < cutoff {
            try permanentlyDelete(id: item.id)
        }
    }

    private func prepareDirectories() throws {
        for url in [layout.entriesURL, layout.originalsURL, layout.thumbnailsURL, layout.corruptEntriesURL, layout.recentlyDeletedURL] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try migrateLegacyAttachments()
    }

    private func migrateLegacyAttachments() throws {
        guard fileManager.fileExists(atPath: layout.attachmentsURL.path) else { return }
        let children = try fileManager.contentsOfDirectory(at: layout.attachmentsURL, includingPropertiesForKeys: [.isRegularFileKey])
        for child in children {
            let values = try child.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let destination = layout.originalsURL.appendingPathComponent(child.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: child, to: destination)
            }
        }
    }

    private func decodeEntry(at url: URL) throws -> DiaryEntry {
        let data = try Data(contentsOf: url)
        if let envelope = try? decoder.decode(DiaryFileEnvelope.self, from: data) {
            guard envelope.formatVersion <= DiaryFileEnvelope.currentFormatVersion else {
                throw DiaryRepositoryError.unsupportedFormat(envelope.formatVersion)
            }
            return envelope.entry
        }
        return try decoder.decode(DiaryEntry.self, from: data)
    }

    private func write(_ entry: DiaryEntry) throws {
        let envelope = DiaryFileEnvelope(entry: entry)
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL(for: entry.id), options: .atomic)
    }

    private func fileURL(for id: UUID) -> URL {
        layout.entriesURL.appendingPathComponent("\(id.uuidString.lowercased()).diaryentry")
    }

    private func existingEntryURL(for id: UUID) throws -> URL? {
        let expected = fileURL(for: id)
        if fileManager.fileExists(atPath: expected.path) { return expected }
        let expectedName = "\(id.uuidString.lowercased()).diaryentry"
        return try fileManager.contentsOfDirectory(at: layout.entriesURL, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.lowercased() == expectedName }
    }

    private func removeLegacyDuplicates(for ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        let currentPaths = Set(ids.map { fileURL(for: $0).standardizedFileURL.path })
        let expectedNames = Set(ids.map { "\($0.uuidString.lowercased()).diaryentry" })
        for file in try fileManager.contentsOfDirectory(at: layout.entriesURL, includingPropertiesForKeys: nil)
        where !currentPaths.contains(file.standardizedFileURL.path)
            && expectedNames.contains(file.lastPathComponent.lowercased()) {
            try fileManager.removeItem(at: file)
        }
    }

    private func uniqueRecoveryURL(for file: URL) -> URL {
        layout.corruptEntriesURL.appendingPathComponent("\(UUID().uuidString)-\(file.lastPathComponent)")
    }

    private func moveIfPresent(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw DiaryRepositoryError.destinationExists(destination.lastPathComponent)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    private func copyIfPresent(from source: URL, to destination: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: source.path) else { return false }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw DiaryRepositoryError.destinationExists(destination.lastPathComponent)
        }
        try fileManager.copyItem(at: source, to: destination)
        return true
    }

    private func validateAttachmentFilename(_ filename: String) throws {
        let allowedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"])
        let stem = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        guard filename == (filename as NSString).lastPathComponent,
              !filename.contains(".."),
              !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              UUID(uuidString: stem) != nil,
              allowedExtensions.contains(pathExtension) else {
            throw DiaryRepositoryError.invalidAttachmentFilename(filename)
        }
    }

    private func rollbackDeletedItem(at itemURL: URL, entry: DiaryEntry) throws {
        for attachment in entry.attachments {
            try moveIfPresent(from: itemURL.appendingPathComponent("Originals/\(attachment.filename)"), to: layout.originalsURL.appendingPathComponent(attachment.filename))
            try moveIfPresent(from: itemURL.appendingPathComponent("Thumbnails/\(attachment.thumbnailFilename)"), to: layout.thumbnailsURL.appendingPathComponent(attachment.thumbnailFilename))
        }
        try? fileManager.removeItem(at: itemURL)
    }
}

enum DiaryRepositoryError: LocalizedError, Sendable {
    case entryNotFound(UUID)
    case unsupportedFormat(Int)
    case recentlyDeletedItemExists(UUID)
    case destinationExists(String)
    case invalidAttachmentFilename(String)

    var errorDescription: String? {
        switch self {
        case .entryNotFound(let id): "日记条目未找到：\(id)"
        case .unsupportedFormat(let version): "日记格式版本过新：\(version)"
        case .recentlyDeletedItemExists: "最近删除中已存在该日记"
        case .destinationExists(let name): "目标文件已存在：\(name)"
        case .invalidAttachmentFilename(let name): "附件文件名不安全：\(name)"
        }
    }
}
