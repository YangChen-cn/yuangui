import Foundation

protocol ChatHistoryStoring: AnyObject {
    func loadMetadata() throws -> [ChatSessionMetadata]
    func loadSession(id: UUID) throws -> ChatSession?
    func save(session: ChatSession, metadata: [ChatSessionMetadata]) throws
    func deleteSession(id: UUID, metadata: [ChatSessionMetadata]) throws
    func clear() throws
}

final class ChatHistoryFileStore: ChatHistoryStoring, @unchecked Sendable {
    private let directoryURL: URL
    private let sessionsDirectoryURL: URL
    private let indexURL: URL
    private let legacyFileURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuanGUI/ChatHistory", isDirectory: true)
        self.directoryURL = directory
        self.sessionsDirectoryURL = directory.appendingPathComponent("Sessions", isDirectory: true)
        self.indexURL = directory.appendingPathComponent("index.json")
        self.legacyFileURL = directory.appendingPathComponent("sessions.json")
        self.fileManager = fileManager
    }

    func loadMetadata() throws -> [ChatSessionMetadata] {
        try migrateLegacyHistoryIfNeeded()
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder.chatHistory.decode([ChatSessionMetadata].self, from: Data(contentsOf: indexURL))
    }

    func loadSession(id: UUID) throws -> ChatSession? {
        let url = sessionURL(id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.chatHistory.decode(ChatSession.self, from: Data(contentsOf: url))
    }

    func save(session: ChatSession, metadata: [ChatSessionMetadata]) throws {
        try ensureDirectory()
        try write(JSONEncoder.chatHistory.encode(session), to: sessionURL(session.id))
        try write(JSONEncoder.chatHistory.encode(metadata), to: indexURL)
    }

    func deleteSession(id: UUID, metadata: [ChatSessionMetadata]) throws {
        let url = sessionURL(id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try ensureDirectory()
        try write(JSONEncoder.chatHistory.encode(metadata), to: indexURL)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: directoryURL.path) { try fileManager.removeItem(at: directoryURL) }
    }

    private func migrateLegacyHistoryIfNeeded() throws {
        guard !fileManager.fileExists(atPath: indexURL.path),
              fileManager.fileExists(atPath: legacyFileURL.path) else { return }
        let sessions = try JSONDecoder.chatHistory.decode([ChatSession].self, from: Data(contentsOf: legacyFileURL))
            .sorted { $0.updatedAt > $1.updatedAt }
        try ensureDirectory()
        for session in sessions {
            try write(JSONEncoder.chatHistory.encode(session), to: sessionURL(session.id))
        }
        try write(JSONEncoder.chatHistory.encode(sessions.map(ChatSessionMetadata.init)), to: indexURL)
        try fileManager.removeItem(at: legacyFileURL)
    }

    private func sessionURL(_ id: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessionsDirectoryURL.path)
    }
}

actor ChatHistoryActor {
    private let store: ChatHistoryStoring
    private var pendingSessions: [UUID: ChatSession] = [:]
    private var pendingMetadata: [ChatSessionMetadata] = []
    private var pendingSaveTask: Task<Void, Never>?

    init(store: ChatHistoryStoring = ChatHistoryFileStore()) {
        self.store = store
    }

    func loadMetadata() throws -> [ChatSessionMetadata] { try store.loadMetadata() }
    func loadSession(id: UUID) throws -> ChatSession? { try store.loadSession(id: id) }

    func scheduleSave(session: ChatSession, metadata: [ChatSessionMetadata]) {
        pendingSessions[session.id] = session
        pendingMetadata = metadata
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.flushPendingSaves()
        }
    }

    func deleteSession(id: UUID, metadata: [ChatSessionMetadata]) throws {
        pendingSessions[id] = nil
        pendingMetadata = metadata
        try store.deleteSession(id: id, metadata: metadata)
    }

    func clear() throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        pendingSessions.removeAll()
        pendingMetadata.removeAll()
        try store.clear()
    }

    private func flushPendingSaves() {
        let sessions = pendingSessions.values
        let metadata = pendingMetadata
        pendingSessions.removeAll()
        pendingSaveTask = nil
        for session in sessions {
            try? store.save(session: session, metadata: metadata)
        }
    }
}

private extension JSONEncoder {
    static var chatHistory: JSONEncoder {
        let encoder = JSONEncoder()
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
