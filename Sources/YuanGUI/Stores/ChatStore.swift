import Foundation

@MainActor
final class ChatStore: ObservableObject {
    static let maximumSessions = 100
    static let maximumMessagesPerSession = 200
    /// Streaming providers can deliver dozens of fragments per second. Keep
    /// the reply responsive without invalidating the SwiftUI tree for every
    /// token.
    static let partialReplyUpdateInterval = Duration.milliseconds(50)

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
    private var pendingPartialReply: (sessionID: UUID, content: String)?
    private var partialReplyUpdateTask: Task<Void, Never>?
    private let partialReplyDelay: (Duration) async throws -> Void
    var onWillPresentationChange: ((Bool) -> Void)?

    init(
        settings: AISettingsStore,
        service: AIChatServicing = AIChatService(),
        history: ChatHistoryStoring = ChatHistoryFileStore(),
        partialReplyDelay: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.settings = settings
        self.service = service
        self.history = ChatHistoryActor(store: history)
        self.partialReplyDelay = partialReplyDelay
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
        if currentSessionID == nil { newSession() }
        guard let targetSessionID = currentSessionID else { return }
        cancelPendingPartialReply()
        latestReply = nil
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        let displayContent = content.isEmpty ? "请看看这些附件" : content
        let userMessage = ChatMessage(role: .user, content: displayContent, attachments: attachments.map(\.metadata))
        guard append(userMessage, to: targetSessionID) else { return }
        let requestMessages = sessions.first(where: { $0.id == targetSessionID })?.messages ?? [userMessage]
        do {
            let reply = try await service.streamReply(
                messages: Array(requestMessages.suffix(12)),
                attachments: attachments,
                configuration: AIChatConfiguration(
                    baseURL: settings.baseURL,
                    model: settings.model,
                    apiKey: settings.apiKey,
                    systemPrompt: settings.systemPrompt,
                    language: settings.promptLanguage
                ),
                petMode: petMode,
                onPartialReply: { [weak self] partialReply in
                    guard let self,
                          self.currentSessionID == targetSessionID,
                          self.sessions.contains(where: { $0.id == targetSessionID }) else { return }
                    self.enqueuePartialReply(partialReply, for: targetSessionID)
                }
            )
            // The completed assistant message publishes the final text once;
            // do not publish the last partial immediately before it.
            cancelPendingPartialReply()
            _ = append(ChatMessage(role: .assistant, content: reply), to: targetSessionID)
        } catch {
            cancelPendingPartialReply()
            if currentSessionID == targetSessionID,
               sessions.contains(where: { $0.id == targetSessionID }) {
                latestReply = nil
                errorMessage = error.localizedDescription
            }
        }
        cancelPendingPartialReply()
    }

    func clear() {
        cancelPendingPartialReply()
        latestReply = nil
        errorMessage = nil
    }

    func newSession() {
        cancelPendingPartialReply()
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
        cancelPendingPartialReply()
        currentSessionID = id
        latestReply = nil
        errorMessage = nil
        Task { await loadSessionIfNeeded(id) }
    }

    func deleteSession(_ id: UUID) {
        if currentSessionID == id { cancelPendingPartialReply() }
        sessions.removeAll { $0.id == id }
        loadedSessionIDs.remove(id)
        sessionMessageCounts[id] = nil
        if currentSessionID == id {
            currentSessionID = sessions.first?.id
            latestReply = nil
            errorMessage = nil
            if let currentSessionID {
                publishLatestVisibleReply()
                Task { await loadSessionIfNeeded(currentSessionID) }
            }
        }
        let metadata = metadataSnapshot()
        Task { try? await history.deleteSession(id: id, metadata: metadata) }
    }

    func clearHistory() {
        cancelPendingPartialReply()
        sessions = []
        loadedSessionIDs = []
        sessionMessageCounts = [:]
        currentSessionID = nil
        latestReply = nil
        errorMessage = nil
        Task { try? await history.clear() }
    }

    func togglePresented() { setPresented(!isPresented) }
    func present() { setPresented(true) }
    func dismiss() { setPresented(false) }

    private func setPresented(_ presented: Bool) {
        guard presented != isPresented else { return }
        // Window controllers must capture their compact geometry before
        // @Published invalidates SwiftUI and AppKit starts resizing the panel.
        onWillPresentationChange?(presented)
        isPresented = presented
        if presented {
            publishLatestVisibleReply()
        } else {
            partialReplyUpdateTask?.cancel()
            partialReplyUpdateTask = nil
        }
    }

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
              sessions.contains(where: { $0.id == id }) else {
            publishLatestVisibleReply()
            return
        }
        isLoadingSession = true
        defer { isLoadingSession = false }
        if let session = try? await history.loadSession(id: id),
           !loadedSessionIDs.contains(id),
           let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = session
            loadedSessionIDs.insert(id)
            sessionMessageCounts[id] = session.messages.count
        }
        publishLatestVisibleReply()
    }

    private func publishLatestVisibleReply() {
        guard isPresented else { return }
        if let pending = pendingPartialReply,
           pending.sessionID == currentSessionID,
           sessions.contains(where: { $0.id == pending.sessionID }) {
            pendingPartialReply = nil
            latestReply = pending.content
            return
        }
        latestReply = currentSession?.messages.last(where: { $0.role == .assistant })?.content
    }

    private func enqueuePartialReply(_ content: String, for sessionID: UUID) {
        pendingPartialReply = (sessionID, content)
        guard isPresented else { return }
        guard partialReplyUpdateTask == nil else { return }
        partialReplyUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.partialReplyDelay(Self.partialReplyUpdateInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.partialReplyUpdateTask = nil
            self.flushPendingPartialReply()
        }
    }

    private func flushPendingPartialReply() {
        partialReplyUpdateTask?.cancel()
        partialReplyUpdateTask = nil
        guard let pending = pendingPartialReply else { return }
        guard isPresented else { return }
        guard currentSessionID == pending.sessionID,
              sessions.contains(where: { $0.id == pending.sessionID }) else {
            pendingPartialReply = nil
            return
        }
        pendingPartialReply = nil
        latestReply = pending.content
    }

    private func cancelPendingPartialReply() {
        partialReplyUpdateTask?.cancel()
        partialReplyUpdateTask = nil
        pendingPartialReply = nil
    }

    @discardableResult
    private func append(_ message: ChatMessage, to id: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
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
        if currentSessionID == id { publishLatestVisibleReply() }
        return true
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
