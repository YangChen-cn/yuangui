import Foundation

enum CleanupCategory: String, Codable, CaseIterable {
    case appCache
    case oldLog
    case temporary
    case browserCache
    case developerCache
    case orphanedAppData

    var title: String {
        switch self {
        case .appCache: return "应用缓存"
        case .oldLog: return "旧日志与崩溃报告"
        case .temporary: return "安全临时文件"
        case .browserCache: return "浏览器缓存"
        case .developerCache: return "开发工具缓存"
        case .orphanedAppData: return "已卸载软件残留"
        }
    }

    var selectedByDefault: Bool {
        switch self {
        case .appCache, .oldLog: return true
        case .temporary, .browserCache, .developerCache, .orphanedAppData: return false
        }
    }
}

enum CleanupDisposition: String, Codable {
    case permanent
    case recycle
}

struct CleanupCandidate: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let displayName: String
    let category: CleanupCategory
    let disposition: CleanupDisposition
    let byteCount: Int64
    let modifiedAt: Date?

    init(
        id: UUID = UUID(), url: URL, displayName: String, category: CleanupCategory,
        disposition: CleanupDisposition, byteCount: Int64, modifiedAt: Date?
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.category = category
        self.disposition = disposition
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

struct ApplicationCandidate: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let bundleIdentifier: String
    let byteCount: Int64
    let lastUsedAt: Date?
    let residuals: [URL]

    init(id: UUID = UUID(), url: URL, name: String, bundleIdentifier: String, byteCount: Int64, lastUsedAt: Date?, residuals: [URL]) {
        self.id = id
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.byteCount = byteCount
        self.lastUsedAt = lastUsedAt
        self.residuals = residuals
    }
}

struct MaintenanceOperation: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case cleanup, uninstall }
    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let itemCount: Int
    let reclaimedBytes: Int64
    let skipped: [String]
    let errors: [String]

    init(id: UUID = UUID(), date: Date = Date(), kind: Kind, title: String, itemCount: Int, reclaimedBytes: Int64, skipped: [String] = [], errors: [String] = []) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.itemCount = itemCount
        self.reclaimedBytes = reclaimedBytes
        self.skipped = skipped
        self.errors = errors
    }
}
