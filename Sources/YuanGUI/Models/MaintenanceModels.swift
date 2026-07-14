import Foundation

enum MaintenanceRisk: String, Codable, CaseIterable, Comparable {
    case recommended
    case review
    case protected

    static func < (lhs: MaintenanceRisk, rhs: MaintenanceRisk) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .recommended: return 0
        case .review: return 1
        case .protected: return 2
        }
    }

    var title: String {
        switch self {
        case .recommended: return "推荐"
        case .review: return "需检查"
        case .protected: return "受保护"
        }
    }
}

enum OwnershipConfidence: String, Codable {
    case exact
    case inferred
    case shared

    var title: String {
        switch self {
        case .exact: return "精确匹配"
        case .inferred: return "名称推断"
        case .shared: return "可能共享"
        }
    }
}

struct FileIdentity: Codable, Equatable {
    let standardizedPath: String
    let modificationDate: Date?
    let fileSize: Int64?

    static func capture(_ url: URL, fileManager: FileManager = .default) -> FileIdentity {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return FileIdentity(
            standardizedPath: resolved.path,
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize.map(Int64.init)
        )
    }

    func stillMatches(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        return self == Self.capture(url, fileManager: fileManager)
    }
}

enum CleanupCategory: String, Codable, CaseIterable {
    case appCache
    case oldLog
    case crashReport
    case temporary
    case browserCache
    case developerCache
    case orphanedAppData

    var title: String {
        switch self {
        case .appCache: return "应用缓存"
        case .oldLog: return "旧日志"
        case .crashReport: return "崩溃报告"
        case .temporary: return "安全临时文件"
        case .browserCache: return "浏览器缓存"
        case .developerCache: return "开发工具缓存"
        case .orphanedAppData: return "已卸载软件残留"
        }
    }

    var selectedByDefault: Bool {
        switch self {
        case .appCache, .oldLog, .crashReport: return true
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
    let risk: MaintenanceRisk
    let confidence: OwnershipConfidence
    let reason: String
    let selectedByDefault: Bool
    let scannedIdentity: FileIdentity

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        category: CleanupCategory,
        disposition: CleanupDisposition,
        byteCount: Int64,
        modifiedAt: Date?,
        risk: MaintenanceRisk? = nil,
        confidence: OwnershipConfidence = .exact,
        reason: String? = nil,
        selectedByDefault: Bool? = nil,
        scannedIdentity: FileIdentity? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.category = category
        self.disposition = disposition
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
        self.risk = risk ?? (category.selectedByDefault ? .recommended : .review)
        self.confidence = confidence
        self.reason = reason ?? "符合\(category.title)规则"
        self.selectedByDefault = selectedByDefault ?? category.selectedByDefault
        self.scannedIdentity = scannedIdentity ?? .capture(url)
    }
}

enum UninstallComponentKind: String, Codable, CaseIterable {
    case application
    case cache
    case log
    case preference
    case applicationSupport
    case savedState
    case webData
    case container
    case applicationScript
    case crashReport
    case launchAgent
    case sharedContainer
    case systemResidual

    var title: String {
        switch self {
        case .application: return "应用本体"
        case .cache: return "缓存"
        case .log: return "日志"
        case .preference: return "偏好设置"
        case .applicationSupport: return "应用数据"
        case .savedState: return "保存状态"
        case .webData: return "网页数据"
        case .container: return "应用容器"
        case .applicationScript: return "应用脚本"
        case .crashReport: return "崩溃记录"
        case .launchAgent: return "用户后台项"
        case .sharedContainer: return "共享容器"
        case .systemResidual: return "系统级残留"
        }
    }
}

struct UninstallComponent: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let kind: UninstallComponentKind
    let byteCount: Int64
    let risk: MaintenanceRisk
    let confidence: OwnershipConfidence
    let reason: String
    let selectedByDefault: Bool
    let scannedIdentity: FileIdentity

    init(
        id: UUID = UUID(),
        url: URL,
        kind: UninstallComponentKind,
        byteCount: Int64,
        risk: MaintenanceRisk,
        confidence: OwnershipConfidence,
        reason: String,
        selectedByDefault: Bool,
        scannedIdentity: FileIdentity? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.byteCount = byteCount
        self.risk = risk
        self.confidence = confidence
        self.reason = reason
        self.selectedByDefault = selectedByDefault
        self.scannedIdentity = scannedIdentity ?? .capture(url)
    }
}

enum ApplicationSource: String, Equatable {
    case systemApplications
    case utilities
    case setapp
    case userApplications

    var title: String {
        switch self {
        case .systemApplications: return "应用程序"
        case .utilities: return "实用工具"
        case .setapp: return "Setapp"
        case .userApplications: return "用户应用"
        }
    }
}

enum ApplicationManagement: String, Equatable {
    case direct
    case homebrew
    case setapp

    var title: String {
        switch self {
        case .direct: return "普通安装"
        case .homebrew: return "Homebrew 管理"
        case .setapp: return "Setapp 管理"
        }
    }
}

struct ApplicationCandidate: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let bundleIdentifier: String
    let byteCount: Int64
    let lastUsedAt: Date?
    let components: [UninstallComponent]
    let source: ApplicationSource
    let management: ApplicationManagement
    let warnings: [String]
    let removalBlocked: Bool

    var residuals: [URL] { components.filter { $0.kind != .application }.map(\.url) }
    var reclaimableByteCount: Int64 { components.reduce(0) { $0 + $1.byteCount } }

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        bundleIdentifier: String,
        byteCount: Int64,
        lastUsedAt: Date?,
        residuals: [URL]
    ) {
        self.init(
            id: id,
            url: url,
            name: name,
            bundleIdentifier: bundleIdentifier,
            byteCount: byteCount,
            lastUsedAt: lastUsedAt,
            components: [
                UninstallComponent(
                    url: url, kind: .application, byteCount: byteCount, risk: .recommended,
                    confidence: .exact, reason: "选中的应用本体", selectedByDefault: true
                )
            ] + residuals.map {
                UninstallComponent(
                    url: $0, kind: .applicationSupport, byteCount: 0, risk: .review,
                    confidence: .exact, reason: "已确认的用户级残留", selectedByDefault: true
                )
            },
            source: .systemApplications,
            management: .direct,
            warnings: [],
            removalBlocked: false
        )
    }

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        bundleIdentifier: String,
        byteCount: Int64,
        lastUsedAt: Date?,
        components: [UninstallComponent],
        source: ApplicationSource,
        management: ApplicationManagement,
        warnings: [String],
        removalBlocked: Bool
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.byteCount = byteCount
        self.lastUsedAt = lastUsedAt
        self.components = components
        self.source = source
        self.management = management
        self.warnings = warnings
        self.removalBlocked = removalBlocked
    }

    func selectingComponents(_ ids: Set<UUID>) -> ApplicationCandidate {
        ApplicationCandidate(
            id: id,
            url: url,
            name: name,
            bundleIdentifier: bundleIdentifier,
            byteCount: byteCount,
            lastUsedAt: lastUsedAt,
            components: components.filter { ids.contains($0.id) },
            source: source,
            management: management,
            warnings: warnings,
            removalBlocked: removalBlocked
        )
    }
}

struct MaintenanceItemResult: Identifiable, Codable, Equatable {
    enum Outcome: String, Codable { case deleted, trashed, skipped, failed }

    let id: UUID
    let path: String
    let displayName: String
    let outcome: Outcome
    let byteCount: Int64
    let message: String?

    init(
        id: UUID = UUID(),
        path: String,
        displayName: String,
        outcome: Outcome,
        byteCount: Int64,
        message: String? = nil
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.outcome = outcome
        self.byteCount = byteCount
        self.message = message
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
    let permanentlyDeletedBytes: Int64?
    let trashedBytes: Int64?
    let results: [MaintenanceItemResult]?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        title: String,
        itemCount: Int,
        reclaimedBytes: Int64,
        skipped: [String] = [],
        errors: [String] = [],
        permanentlyDeletedBytes: Int64? = nil,
        trashedBytes: Int64? = nil,
        results: [MaintenanceItemResult]? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.itemCount = itemCount
        self.reclaimedBytes = reclaimedBytes
        self.skipped = skipped
        self.errors = errors
        self.permanentlyDeletedBytes = permanentlyDeletedBytes
        self.trashedBytes = trashedBytes
        self.results = results
    }
}
