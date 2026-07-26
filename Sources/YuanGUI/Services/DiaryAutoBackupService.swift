import Foundation

struct DiaryBackupStatus: Equatable, Sendable {
    var lastAutomaticBackup: Date?
    var dailyCount = 0
    var weeklyCount = 0
    var manualCount = 0

    var backupCount: Int { dailyCount + weeklyCount + manualCount }

    static let empty = DiaryBackupStatus()
}

actor DiaryAutoBackupService {
    static let dailyRetentionCount = 7
    static let weeklyRetentionCount = 4

    private enum Prefix {
        static let daily = "每日备份-"
        static let weekly = "每周备份-"
        static let manual = "立即备份-"
    }

    private let layout: DiaryStorageLayout
    private let exportService: DiaryExportService
    private let fileManager: FileManager
    private let calendar: Calendar

    init(
        layout: DiaryStorageLayout,
        exportService: DiaryExportService,
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.layout = layout
        self.exportService = exportService
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func backupIfNeeded(now: Date = Date()) async throws -> DiaryBackupStatus {
        try createBackupDirectoryIfNeeded()
        let dailyURL = layout.backupURL.appendingPathComponent(
            "\(Prefix.daily)\(dayStamp(now)).zip"
        )
        guard !fileManager.fileExists(atPath: dailyURL.path) else {
            return try currentStatus()
        }

        _ = try await exportService.backup(to: dailyURL)
        let weeklyURL = layout.backupURL.appendingPathComponent(
            "\(Prefix.weekly)\(weekStamp(now)).zip"
        )
        if !fileManager.fileExists(atPath: weeklyURL.path) {
            try fileManager.copyItem(at: dailyURL, to: weeklyURL)
        }
        try prune(prefix: Prefix.daily, keeping: Self.dailyRetentionCount)
        try prune(prefix: Prefix.weekly, keeping: Self.weeklyRetentionCount)
        return try currentStatus()
    }

    func backupNow(now: Date = Date()) async throws -> (URL, DiaryBackupStatus) {
        try createBackupDirectoryIfNeeded()
        let destination = uniqueManualBackupURL(now: now)
        let result = try await exportService.backup(to: destination)
        return (result, try currentStatus())
    }

    func status() throws -> DiaryBackupStatus {
        try currentStatus()
    }

    private func currentStatus() throws -> DiaryBackupStatus {
        guard fileManager.fileExists(atPath: layout.backupURL.path) else {
            return .empty
        }
        let files = try backupFiles()
        let daily = files.filter { $0.lastPathComponent.hasPrefix(Prefix.daily) }
        let weekly = files.filter { $0.lastPathComponent.hasPrefix(Prefix.weekly) }
        let manual = files.filter { $0.lastPathComponent.hasPrefix(Prefix.manual) }
        let automaticDates = try (daily + weekly).compactMap(modificationDate)
        return DiaryBackupStatus(
            lastAutomaticBackup: automaticDates.max(),
            dailyCount: daily.count,
            weeklyCount: weekly.count,
            manualCount: manual.count
        )
    }

    private func prune(prefix: String, keeping limit: Int) throws {
        let files = try backupFiles()
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted {
                (try? modificationDate($0)) ?? .distantPast
                    > ((try? modificationDate($1)) ?? .distantPast)
            }
        for url in files.dropFirst(limit) {
            try fileManager.removeItem(at: url)
        }
    }

    private func backupFiles() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: layout.backupURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "zip" }
    }

    private func modificationDate(_ url: URL) throws -> Date? {
        try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func createBackupDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: layout.backupURL,
            withIntermediateDirectories: true
        )
    }

    private func uniqueManualBackupURL(now: Date) -> URL {
        let base = "\(Prefix.manual)\(timestamp(now))"
        var candidate = layout.backupURL.appendingPathComponent("\(base).zip")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = layout.backupURL.appendingPathComponent("\(base)-\(suffix).zip")
            suffix += 1
        }
        return candidate
    }

    private func dayStamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private func weekStamp(_ date: Date) -> String {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        let parts = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(
            format: "%04d-W%02d",
            parts.yearForWeekOfYear ?? 0,
            parts.weekOfYear ?? 0
        )
    }

    private func timestamp(_ date: Date) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d-%02d%02d%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }
}
