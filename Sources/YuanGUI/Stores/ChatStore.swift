import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var latestReply: String?
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPresented = false
    @Published private(set) var sessions: [ChatSession]
    @Published private(set) var currentSessionID: UUID?

    let settings: AISettingsStore
    private let service: AIChatServicing
    private let history: ChatHistoryStoring

    init(
        settings: AISettingsStore,
        service: AIChatServicing = AIChatService(),
        history: ChatHistoryStoring = ChatHistoryFileStore()
    ) {
        self.settings = settings
        self.service = service
        self.history = history
        self.sessions = (try? history.loadSessions())?.sorted { $0.updatedAt > $1.updatedAt } ?? []
        self.currentSessionID = self.sessions.first?.id
    }

    var currentSession: ChatSession? {
        guard let id = currentSessionID else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    func send(_ text: String, attachments: [PreparedChatAttachment] = [], petMode: PetMode) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!content.isEmpty || !attachments.isEmpty), !isSending else { return }
        latestReply = nil
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        let displayContent = content.isEmpty ? "请看看这些附件" : content
        let userMessage = ChatMessage(
            role: .user,
            content: displayContent,
            attachments: attachments.map(\.metadata)
        )
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
        currentSessionID = session.id
        latestReply = nil
        errorMessage = nil
        persist()
    }

    func selectSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentSessionID = id
        let latestAssistant = sessions.first(where: { $0.id == id })?.messages.last(where: { $0.role == .assistant })
        latestReply = latestAssistant?.content
        errorMessage = nil
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if currentSessionID == id { currentSessionID = sessions.first?.id }
        persist()
    }

    func clearHistory() {
        sessions = []
        currentSessionID = nil
        latestReply = nil
        errorMessage = nil
        try? history.clear()
    }

    func showHistory() {
        NotificationCenter.default.post(name: .showYuanGUIChatHistory, object: nil)
    }

    func togglePresented() {
        isPresented.toggle()
    }

    func present() { isPresented = true }
    func dismiss() { isPresented = false }

    private func append(_ message: ChatMessage) {
        if currentSessionID == nil { newSession() }
        guard let id = currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].messages.append(message)
        sessions[index].updatedAt = Date()
        if sessions[index].title == "新对话", message.role == .user {
            sessions[index].title = String(message.content.prefix(24))
        }
        let session = sessions.remove(at: index)
        sessions.insert(session, at: 0)
        persist()
    }

    private func persist() {
        do { try history.saveSessions(sessions) }
        catch { errorMessage = "对话历史保存失败：\(error.localizedDescription)" }
    }
}
