import Foundation

struct DiaryStorageLayout: Sendable {
    let rootURL: URL
    let backupURL: URL
    let temporaryURL: URL

    init(rootURL: URL, backupURL: URL? = nil, temporaryURL: URL? = nil) {
        self.rootURL = rootURL
        self.backupURL = backupURL ?? rootURL.deletingLastPathComponent().appendingPathComponent("DiaryBackups", isDirectory: true)
        self.temporaryURL = temporaryURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("YuanGUI-Diary", isDirectory: true)
    }

    static var production: DiaryStorageLayout {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yuanGUI = appSupport.appendingPathComponent("YuanGUI", isDirectory: true)
        return DiaryStorageLayout(
            rootURL: yuanGUI.appendingPathComponent("Diary", isDirectory: true),
            backupURL: yuanGUI.appendingPathComponent("DiaryBackups", isDirectory: true)
        )
    }

    var entriesURL: URL { rootURL.appendingPathComponent("Entries", isDirectory: true) }
    var attachmentsURL: URL { rootURL.appendingPathComponent("Attachments", isDirectory: true) }
    var originalsURL: URL { attachmentsURL.appendingPathComponent("Originals", isDirectory: true) }
    var thumbnailsURL: URL { attachmentsURL.appendingPathComponent("Thumbnails", isDirectory: true) }
    var recoveryURL: URL { rootURL.appendingPathComponent("Recovery", isDirectory: true) }
    var corruptEntriesURL: URL { recoveryURL.appendingPathComponent("CorruptEntries", isDirectory: true) }
    var recentlyDeletedURL: URL { rootURL.appendingPathComponent("RecentlyDeleted", isDirectory: true) }
}

struct DiaryFileEnvelope: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let entry: DiaryEntry

    init(formatVersion: Int = currentFormatVersion, entry: DiaryEntry) {
        self.formatVersion = formatVersion
        self.entry = entry
    }
}

struct DiaryLoadReport: Sendable {
    let entries: [DiaryEntry]
    let recoveredFiles: [URL]
}

struct DiaryWriteFailure: Identifiable, Equatable, Sendable {
    let entryID: UUID
    let message: String

    var id: UUID { entryID }
}

struct DiarySaveReport: Equatable, Sendable {
    let savedIDs: Set<UUID>
    let failures: [DiaryWriteFailure]

    var succeeded: Bool { failures.isEmpty }
}

struct DiaryDeletedItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let entry: DiaryEntry
    let deletedAt: Date
}

struct DiaryDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var occurredAt: Date
    var mood: DiaryMood?
    var tags: [String]
    var locationName: String

    init(entry: DiaryEntry) {
        id = entry.id
        title = entry.title ?? ""
        body = entry.body
        occurredAt = entry.occurredAt
        mood = entry.mood
        tags = entry.tags
        locationName = entry.locationName ?? ""
    }
}

struct DiaryFilter: Equatable, Sendable {
    var month: Date?
    var day: Date?
    var tag: String?
    var favoritesOnly = false
}

enum DiaryLoadState: Equatable, Sendable {
    case unloaded
    case loading
    case loaded
    case failed(String)
}

enum DiarySaveState: Equatable, Sendable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

struct DiaryExportDocument: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let entries: [DiaryEntry]
}

struct DiaryBackupManifest: Codable, Sendable {
    struct FileRecord: Codable, Sendable {
        let path: String
        let byteCount: Int
        let sha256: String
    }

    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let entryCount: Int
    let files: [FileRecord]
}

