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
        XCTAssertEqual(settings.model, "mimo-v2.5-pro")
        settings.updateAPIKey("test-key")
        settings.model = "custom-model"
        settings.save()

        XCTAssertEqual(secrets.value, "test-key")
        XCTAssertEqual(defaults.string(forKey: "aiModel"), "custom-model")
    }
}

private final class MemorySecretStore: SecretStoring {
    var value: String?
    func read(service: String, account: String) -> String? { value }
    func save(_ value: String, service: String, account: String) throws { self.value = value }
    func delete(service: String, account: String) throws { value = nil }
}
