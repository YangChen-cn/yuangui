import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var latestReply: String?
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPresented = false

    let settings: AISettingsStore
    private let service: AIChatServicing

    init(settings: AISettingsStore, service: AIChatServicing = AIChatService()) {
        self.settings = settings
        self.service = service
    }

    func send(_ text: String, petMode: PetMode) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        latestReply = nil
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await service.reply(
                messages: [ChatMessage(role: .user, content: content)],
                configuration: AIChatConfiguration(
                    baseURL: settings.baseURL,
                    model: settings.model,
                    apiKey: settings.apiKey,
                    systemPrompt: settings.systemPrompt
                ),
                petMode: petMode
            )
            latestReply = reply
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        latestReply = nil
        errorMessage = nil
    }

    func togglePresented() {
        isPresented.toggle()
    }

    func present() { isPresented = true }
    func dismiss() { isPresented = false }
}
