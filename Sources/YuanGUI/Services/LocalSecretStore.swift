import Foundation

protocol SecretStoring {
    func read(service: String, account: String) -> String?
    func save(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct LocalSecretStore: SecretStoring {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        self.fileURL = base
            .appendingPathComponent("YuanGUI", isDirectory: true)
            .appendingPathComponent("ai-api-key", isDirectory: false)
    }

    func read(service: String, account: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    func save(_ value: String, service: String, account: String) throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let data = Data(value.utf8)
        if !manager.fileExists(atPath: fileURL.path) {
            guard manager.createFile(
                atPath: fileURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw LocalSecretError.cannotCreateFile
            }
        } else {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func delete(service: String, account: String) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

private enum LocalSecretError: LocalizedError {
    case cannotCreateFile

    var errorDescription: String? {
        "无法创建本地 API Key 文件"
    }
}
