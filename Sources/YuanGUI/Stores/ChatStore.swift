import Foundation

@MainActor
final class ChatStore: ObservableObject {
    static let maximumSessions = 100
    static let maximumMessagesPerSession = 200

    @Published private(set) var latestReply: String?
    @Published private(set) var isSending = false
    @Published private(set) var isLoadingSession = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPresented = false
    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var currentSessionID: UUID?

    let settings: AISettingsStore
    private let service: AIChatServicing
    private let history: ChatHistoryActor
    private var loadedSessionIDs = Set<UUID>()
    private var sessionMessageCounts: [UUID: Int] = [:]
    private var hasBootstrapped = false
    private var bootstrapWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settings: AISettingsStore,
        service: AIChatServicing = AIChatService(),
        history: ChatHistoryStoring = ChatHistoryFileStore()
    ) {
        self.settings = settings
        self.service = service
        self.history = ChatHistoryActor(store: history)
        Task { await bootstrap() }
    }

    var currentSession: ChatSession? {
        guard let id = currentSessionID else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    func messageCount(for id: UUID) -> Int {
        sessionMessageCounts[id] ?? sessions.first(where: { $0.id == id })?.messages.count ?? 0
    }

    func send(_ text: String, attachments: [PreparedChatAttachment] = [], petMode: PetMode) async {
        await waitUntilBootstrapped()
        await ensureCurrentSessionLoaded()
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!content.isEmpty || !attachments.isEmpty), !isSending else { return }
        latestReply = nil
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        let displayContent = content.isEmpty ? "请看看这些附件" : content
        let userMessage = ChatMessage(role: .user, content: displayContent, attachments: attachments.map(\.metadata))
        append(userMessage)
        do {
            let reply = try await service.reply(
                messages: Array((currentSession?.messages ?? [userMessage]).suffix(12)),
                attachments: attachments,
                configuration: AIChatConfiguration(
                    baseURL: settings.baseURL,
                    model: settings.model,
                    apiKey: settings.apiKey,
                    systemPrompt: settings.systemPrompt
                ),
                petMode: petMode
            )
            latestReply = reply
            append(ChatMessage(role: .assistant, content: reply))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        latestReply = nil
        errorMessage = nil
    }

    func newSession() {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        loadedSessionIDs.insert(session.id)
        sessionMessageCounts[session.id] = 0
        currentSessionID = session.id
        latestReply = nil
        errorMessage = nil
        trimSessionLimit()
    }

    func selectSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentSessionID = id
        latestReply = nil
        errorMessage = nil
        Task { await loadSessionIfNeeded(id) }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        loadedSessionIDs.remove(id)
        sessionMessageCounts[id] = nil
        if currentSessionID == id {
            currentSessionID = sessions.first?.id
            if let currentSessionID { Task { await loadSessionIfNeeded(currentSessionID) } }
        }
        let metadata = metadataSnapshot()
        Task { try? await history.deleteSession(id: id, metadata: metadata) }
    }

    func clearHistory() {
        sessions = []
        loadedSessionIDs = []
        sessionMessageCounts = [:]
        currentSessionID = nil
        latestReply = nil
        errorMessage = nil
        Task { try? await history.clear() }
    }

    func showHistory() { NotificationCenter.default.post(name: .showYuanGUIChatHistory, object: nil) }
    func togglePresented() { isPresented.toggle() }
    func present() { isPresented = true }
    func dismiss() { isPresented = false }

    private func bootstrap() async {
        let metadata = (try? await history.loadMetadata()) ?? []
        sessions = metadata.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.maximumSessions).map(\.placeholder)
        sessionMessageCounts = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0.messageCount) })
        newSession()
        hasBootstrapped = true
        let waiters = bootstrapWaiters
        bootstrapWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitUntilBootstrapped() async {
        if hasBootstrapped { return }
        await withCheckedContinuation { bootstrapWaiters.append($0) }
    }

    private func ensureCurrentSessionLoaded() async {
        guard let id = currentSessionID else { return }
        await loadSessionIfNeeded(id)
    }

    private func loadSessionIfNeeded(_ id: UUID) async {
        guard !loadedSessionIDs.contains(id),
              let index = sessions.firstIndex(where: { $0.id == id }) else {
            updateLatestReply()
            return
        }
        isLoadingSession = true
        defer { isLoadingSession = false }
        if let session = try? await history.loadSession(id: id) {
            sessions[index] = session
            loadedSessionIDs.insert(id)
            sessionMessageCounts[id] = session.messages.count
        }
        updateLatestReply()
    }

    private func updateLatestReply() {
        latestReply = currentSession?.messages.last(where: { $0.role == .assistant })?.content
    }

    private func append(_ message: ChatMessage) {
        if currentSessionID == nil { newSession() }
        guard let id = currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].messages.append(message)
        if sessions[index].messages.count > Self.maximumMessagesPerSession {
            sessions[index].messages = Array(sessions[index].messages.suffix(Self.maximumMessagesPerSession))
        }
        sessions[index].updatedAt = Date()
        if sessions[index].title == "新对话", message.role == .user {
            sessions[index].title = String(message.content.prefix(24))
        }
        let session = sessions.remove(at: index)
        sessions.insert(session, at: 0)
        loadedSessionIDs.insert(id)
        sessionMessageCounts[id] = session.messages.count
        trimSessionLimit()
        let metadata = metadataSnapshot()
        Task { await history.scheduleSave(session: session, metadata: metadata) }
    }

    private func trimSessionLimit() {
        guard sessions.count > Self.maximumSessions else { return }
        let removed = sessions.dropFirst(Self.maximumSessions).map(\.id)
        sessions = Array(sessions.prefix(Self.maximumSessions))
        removed.forEach { id in
            loadedSessionIDs.remove(id)
            sessionMessageCounts[id] = nil
            let metadata = metadataSnapshot()
            Task { try? await history.deleteSession(id: id, metadata: metadata) }
        }
    }

    private func metadataSnapshot() -> [ChatSessionMetadata] {
        sessions.map { session in
            var metadata = ChatSessionMetadata(session: session)
            metadata.messageCount = sessionMessageCounts[session.id] ?? session.messages.count
            return metadata
        }
    }
}
