import Foundation

protocol ChatHistoryStoring {
    func loadSessions() throws -> [ChatSession]
    func saveSessions(_ sessions: [ChatSession]) throws
    func deleteSession(id: UUID) throws
    func clear() throws
}

final class ChatHistoryFileStore: ChatHistoryStoring {
    private let directoryURL: URL
    private let fileURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuanGUI/ChatHistory", isDirectory: true)
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent("sessions.json")
        self.fileManager = fileManager
    }

    func loadSessions() throws -> [ChatSession] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder.chatHistory.decode([ChatSession].self, from: Data(contentsOf: fileURL))
    }

    func saveSessions(_ sessions: [ChatSession]) throws {
        try ensureDirectory()
        let data = try JSONEncoder.chatHistory.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func deleteSession(id: UUID) throws {
        try saveSessions(loadSessions().filter { $0.id != id })
    }

    func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }
}

private extension JSONEncoder {
    static var chatHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var chatHistory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
