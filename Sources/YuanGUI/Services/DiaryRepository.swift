import Foundation

/// 日记持久化服务（JSON-per-file 方案）
final class DiaryRepository: Sendable {
    private let entriesURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(baseURL: URL) {
        self.entriesURL = baseURL.appendingPathComponent("Entries", isDirectory: true)
    }

    /// 保存单条日记（原子写入）
    func save(_ entry: DiaryEntry) throws {
        try FileManager.default.createDirectory(at: entriesURL, withIntermediateDirectories: true)
        let data = try encoder.encode(entry)
        let fileURL = entriesURL.appendingPathComponent(filename(for: entry))
        let tmpURL = fileURL.appendingPathExtension("tmp")
        // 先删除同 ID 的旧文件（可能文件名不同，如旧格式日期+UUID）
        let uuidPrefix = entry.id.uuidString.prefix(8).lowercased()
        let oldFiles = try? FileManager.default.contentsOfDirectory(at: entriesURL, includingPropertiesForKeys: nil)
        if let oldFiles {
            for oldFile in oldFiles {
                let name = oldFile.lastPathComponent
                if name.contains(uuidPrefix)
                    && name.hasSuffix(".diaryentry")
                    && oldFile != fileURL {
                    try? FileManager.default.removeItem(at: oldFile)
                }
            }
        }
        // 原子写入
        try data.write(to: tmpURL)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: fileURL)
    }

    /// 加载所有日记
    func loadAll() throws -> [DiaryEntry] {
        guard FileManager.default.fileExists(atPath: entriesURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: entriesURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return try files
            .filter { $0.pathExtension == "diaryentry" }
            .map { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(DiaryEntry.self, from: data)
            }
    }

    /// 按 ID 加载单条
    func load(id: UUID) throws -> DiaryEntry? {
        let all = try loadAll()
        return all.first { $0.id == id }
    }

    /// 删除单条日记（包括所有旧格式文件）
    func delete(id: UUID) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: entriesURL,
            includingPropertiesForKeys: nil
        )
        let uuidPrefix = id.uuidString.prefix(8).lowercased()
        var deleted = false
        for file in files where file.lastPathComponent.contains(uuidPrefix)
                && file.lastPathComponent.hasSuffix(".diaryentry") {
            try FileManager.default.removeItem(at: file)
            deleted = true
        }
        guard deleted else { throw DiaryRepositoryError.entryNotFound(id) }
    }

    /// "那年今日"查询：返回去年今天 ±3 天的日记
    func entriesForOnThisDay(referenceDate: Date = Date()) throws -> [DiaryEntry] {
        let calendar = Calendar.current
        let all = try loadAll()
        return all.filter { entry in
            guard let lastYear = calendar.date(byAdding: .year, value: -1, to: referenceDate) else {
                return false
            }
            let daysDiff = abs(calendar.dateComponents([.day], from: lastYear, to: entry.occurredAt).day ?? 999)
            return daysDiff <= 3
        }
    }

    // MARK: - Private

    private func filename(for entry: DiaryEntry) -> String {
        let uuidStr = entry.id.uuidString.lowercased()
        return "\(uuidStr).diaryentry"
    }

    private func fileURL(for id: UUID) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(
            at: entriesURL,
            includingPropertiesForKeys: nil
        )
        guard let url = files.first(where: { $0.lastPathComponent.contains(id.uuidString.prefix(8).lowercased()) }) else {
            throw DiaryRepositoryError.entryNotFound(id)
        }
        return url
    }
}

enum DiaryRepositoryError: LocalizedError {
    case entryNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .entryNotFound(let id):
            "日记条目未找到: \(id)"
        }
    }
}
