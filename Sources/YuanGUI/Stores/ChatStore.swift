import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    let settings: AISettingsStore
    private let service: AIChatServicing

    init(settings: AISettingsStore, service: AIChatServicing = AIChatService()) {
        self.settings = settings
        self.service = service
    }

    func send(_ text: String, petMode: PetMode) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        messages.append(ChatMessage(role: .user, content: content))
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await service.reply(
                messages: messages,
                configuration: AIChatConfiguration(
                    baseURL: settings.baseURL,
                    model: settings.model,
                    apiKey: settings.apiKey,
                    systemPrompt: settings.systemPrompt
                ),
                petMode: petMode
            )
            messages.append(ChatMessage(role: .assistant, content: reply))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        messages.removeAll()
        errorMessage = nil
    }
}
