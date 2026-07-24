import Foundation

/// 日记导出与备份服务
final class DiaryExportService: Sendable {
    private let repository: DiaryRepository
    private let attachmentStore: DiaryAttachmentStore
    private let exportDir: URL

    init(repository: DiaryRepository, attachmentStore: DiaryAttachmentStore) {
        self.repository = repository
        self.attachmentStore = attachmentStore
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.exportDir = appSupport.appendingPathComponent("YuanGUI/Diary/Exports", isDirectory: true)
    }

    /// 导出为 Markdown 文件
    func exportMarkdown(entries: [DiaryEntry]) throws -> URL {
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        var md = "# 元圭恋爱手账\n\n"
        md += "导出时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        md += "共 \(entries.count) 条日记\n\n---\n\n"
        for entry in entries.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            md += "## \(entry.title ?? entry.displayTitle)\n\n"
            md += "**日期：** \(formatter.string(from: entry.occurredAt))"
            if let mood = entry.mood { md += "　　**心情：** \(mood.emoji) \(mood.title)" }
            md += "\n\n"
            if !entry.tags.isEmpty { md += "**标签：** \(entry.tags.joined(separator: "、"))\n\n" }
            md += entry.body
            md += "\n\n---\n\n"
        }
        let url = exportDir.appendingPathComponent("恋爱手账-\(dateStamp()).md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 导出为 JSON
    func exportJSON(entries: [DiaryEntry]) throws -> URL {
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(entries)
        let url = exportDir.appendingPathComponent("恋爱手账-\(dateStamp()).json")
        try data.write(to: url)
        return url
    }

    /// 导出为 ZIP（含 JSON + 附件 + README）
    func exportZIP(entries: [DiaryEntry]) throws -> URL {
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let stagingDir = exportDir.appendingPathComponent("staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        // 写入 JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let jsonData = try encoder.encode(entries)
        try jsonData.write(to: stagingDir.appendingPathComponent("entries.json"))

        // 写入 README
        let readme = """
        # 元圭恋爱手账导出

        导出时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))
        共 \(entries.count) 条日记

        ## 文件说明
        - entries.json: 所有日记数据（JSON 格式）
        - Attachments/: 附件图片
        - 可使用 JSON 文件重新导入 YuanGUI
        """
        try readme.write(to: stagingDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        // 复制附件
        let attachDir = stagingDir.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)
        for entry in entries {
            for attachment in entry.attachments {
                let src = attachmentStore.path(for: attachment)
                let dst = attachDir.appendingPathComponent(attachment.filename)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }

        // 创建 ZIP
        let zipURL = exportDir.appendingPathComponent("恋爱手账-\(dateStamp()).zip")
        try? FileManager.default.removeItem(at: zipURL) // 移除旧文件
        try zipDirectory(source: stagingDir, destination: zipURL)
        return zipURL
    }

    /// 完整备份
    func backup() throws -> URL {
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let diaryDir = appSupport.appendingPathComponent("YuanGUI/Diary", isDirectory: true)
        let zipURL = exportDir.appendingPathComponent("恋爱手账备份-\(dateStamp()).zip")
        try? FileManager.default.removeItem(at: zipURL)
        try zipDirectory(source: diaryDir, destination: zipURL)
        return zipURL
    }

    /// 从备份恢复
    func restore(from backupURL: URL) throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let diaryDir = appSupport.appendingPathComponent("YuanGUI/Diary", isDirectory: true)
        let tmpDir = exportDir.appendingPathComponent("restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 解压到临时目录
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", backupURL.path, "-d", tmpDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // 复制到目标目录
        if FileManager.default.fileExists(atPath: diaryDir.path) {
            try FileManager.default.removeItem(at: diaryDir)
        }
        try FileManager.default.copyItem(at: tmpDir, to: diaryDir)
    }

    // MARK: - Private

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func zipDirectory(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-j", destination.path, source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DiaryExportError.zipFailed
        }
    }
}

enum DiaryExportError: LocalizedError {
    case zipFailed
    var errorDescription: String? { "ZIP 创建失败" }
}
