import Foundation
import XCTest
@testable import YuanGUI

final class AIChatTests: XCTestCase {
    func testChatEndpointAppendsPathToBaseURL() {
        XCTAssertEqual(
            AIChatService.chatEndpoint(from: "https://api.xiaomimimo.com/v1")?.absoluteString,
            "https://api.xiaomimimo.com/v1/chat/completions"
        )
        XCTAssertEqual(
            AIChatService.chatEndpoint(from: "https://example.com/v1/chat/completions")?.absoluteString,
            "https://example.com/v1/chat/completions"
        )
    }

    func testChatEndpointRejectsInvalidAddress() {
        XCTAssertNil(AIChatService.chatEndpoint(from: "not a url"))
        XCTAssertNil(AIChatService.chatEndpoint(from: "ftp://example.com/v1"))
    }

    @MainActor
    func testSettingsUseMiMoDefaultsAndPersistWithoutRealKeychain() {
        let suite = "AISettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecretStore()
        let settings = AISettingsStore(defaults: defaults, secrets: secrets)

        XCTAssertEqual(settings.baseURL, AISettingsStore.defaultBaseURL)
        XCTAssertEqual(settings.model, "mimo-v2.5")
        settings.updateAPIKey("test-key")
        settings.model = "custom-model"
        settings.save()

        XCTAssertEqual(secrets.value, "test-key")
        XCTAssertEqual(defaults.string(forKey: "aiModel"), "custom-model")
    }

    @MainActor
    func testChatKeepsOnlyLatestReplyAndSendsNoHistory() async {
        let suite = "ChatStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecretStore()
        secrets.value = "test-key"
        let settings = AISettingsStore(defaults: defaults, secrets: secrets)
        let service = SequencedChatService(replies: ["第一次回复", "第二次回复"])
        let chat = ChatStore(settings: settings, service: service)

        await chat.send("第一问", petMode: .duo)
        XCTAssertEqual(chat.latestReply, "第一次回复")
        await chat.send("第二问", petMode: .duo)

        XCTAssertEqual(chat.latestReply, "第二次回复")
        let received = await service.receivedContents()
        XCTAssertEqual(received, [["第一问"], ["第二问"]])
    }
}

private final class MemorySecretStore: SecretStoring {
    var value: String?
    func read(service: String, account: String) -> String? { value }
    func save(_ value: String, service: String, account: String) throws { self.value = value }
    func delete(service: String, account: String) throws { value = nil }
}

private actor SequencedChatService: AIChatServicing {
    private var replies: [String]
    private var received: [[String]] = []

    init(replies: [String]) {
        self.replies = replies
    }

    func reply(
        messages: [ChatMessage],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String {
        received.append(messages.map(\.content))
        return replies.removeFirst()
    }

    func receivedContents() -> [[String]] { received }
}
