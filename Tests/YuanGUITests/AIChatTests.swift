import AppKit
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

    func testLocalSecretStorePersistsWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSecretStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("ai-api-key")
        let store = LocalSecretStore(fileURL: file)

        try store.save("test-secret", service: "test", account: "default")

        XCTAssertEqual(store.read(service: "test", account: "default"), "test-secret")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        try store.delete(service: "test", account: "default")
        XCTAssertNil(store.read(service: "test", account: "default"))
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
    func testChatKeepsLatestBubbleAndSendsCurrentSessionContext() async {
        let suite = "ChatStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecretStore()
        secrets.value = "test-key"
        let settings = AISettingsStore(defaults: defaults, secrets: secrets)
        let service = SequencedChatService(replies: ["第一次回复", "第二次回复"])
        let history = MemoryChatHistoryStore()
        let chat = ChatStore(settings: settings, service: service, history: history)

        await chat.send("第一问", petMode: .duo)
        XCTAssertEqual(chat.latestReply, "第一次回复")
        await chat.send("第二问", petMode: .duo)

        XCTAssertEqual(chat.latestReply, "第二次回复")
        let received = await service.receivedContents()
        XCTAssertEqual(received, [["第一问"], ["第一问", "第一次回复", "第二问"]])
        XCTAssertEqual(chat.sessions.first?.messages.count, 4)
    }

    func testChatHistoryFileStorePersistsDeletesAndProtectsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatHistoryFileStore(directoryURL: directory)
        let session = ChatSession(title: "测试", messages: [ChatMessage(role: .user, content: "你好")])

        try store.saveSessions([session])

        let loaded = try store.loadSessions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, session.id)
        XCTAssertEqual(loaded.first?.title, session.title)
        XCTAssertEqual(loaded.first?.messages.map(\.content), ["你好"])
        XCTAssertEqual(loaded.first?.createdAt.timeIntervalSince1970 ?? 0, session.createdAt.timeIntervalSince1970, accuracy: 1)
        let file = directory.appendingPathComponent("sessions.json")
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try store.deleteSession(id: session.id)
        XCTAssertEqual(try store.loadSessions(), [])
    }

    func testAttachmentPreparerExtractsAndTruncatesText() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("large-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try String(repeating: "元", count: AttachmentPreparer.maximumCharacters + 20).write(to: file, atomically: true, encoding: .utf8)

        let prepared = try AttachmentPreparer().prepare(url: file)

        XCTAssertTrue(prepared.metadata.wasTruncated)
        if case .extractedText(let content) = prepared.payload {
            XCTAssertEqual(content.count, AttachmentPreparer.maximumCharacters)
        } else {
            XCTFail("Expected extracted text")
        }
    }

    func testAttachmentPreparerResizesImageAsBase64DataURL() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("image-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let image = NSImage(size: NSSize(width: 16, height: 8))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 8).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Unable to create fixture")
        }
        try png.write(to: file)

        let prepared = try AttachmentPreparer().prepare(url: file)

        XCTAssertEqual(prepared.metadata.kind, .image)
        if case .imageDataURL(let value) = prepared.payload {
            XCTAssertTrue(value.hasPrefix("data:image/jpeg;base64,"))
            XCTAssertNotNil(Data(base64Encoded: String(value.dropFirst("data:image/jpeg;base64,".count))))
        } else {
            XCTFail("Expected image data URL")
        }
    }

    func testAttachmentPreparerRejectsFilesOverTwentyMegabytes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("oversize-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(AttachmentPreparer.maximumBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try AttachmentPreparer().prepare(url: file))
    }

    func testPasteboardReaderReturnsImageDataAndIgnoresPlainText() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ChatPasteboardTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let image = NSImage(size: NSSize(width: 12, height: 6))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 6).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Unable to create pasteboard fixture")
        }
        let imageItem = NSPasteboardItem()
        imageItem.setData(png, forType: .png)
        XCTAssertTrue(pasteboard.writeObjects([imageItem]))

        let pastedImages = ChatPasteboardReader.images(from: pasteboard)
        XCTAssertEqual(pastedImages.count, 1)
        XCTAssertEqual(pastedImages.first?.suggestedName, "粘贴图片-1.png")
        if case .data(let data) = pastedImages.first?.source {
            XCTAssertEqual(data, png)
        } else {
            XCTFail("Expected pasted image data")
        }

        let imageFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasted-\(UUID().uuidString).png")
        try png.write(to: imageFile)
        defer { try? FileManager.default.removeItem(at: imageFile) }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([imageFile as NSURL]))
        let pastedFiles = ChatPasteboardReader.images(from: pasteboard)
        XCTAssertEqual(pastedFiles.count, 1)
        if case .fileURL(let url) = pastedFiles.first?.source {
            XCTAssertEqual(url.standardizedFileURL, imageFile.standardizedFileURL)
        } else {
            XCTFail("Expected pasted image file URL")
        }

        pasteboard.clearContents()
        pasteboard.setString("普通文字", forType: .string)
        XCTAssertTrue(ChatPasteboardReader.images(from: pasteboard).isEmpty)
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
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String {
        received.append(messages.map(\.content))
        return replies.removeFirst()
    }

    func receivedContents() -> [[String]] { received }
}

private final class MemoryChatHistoryStore: ChatHistoryStoring {
    var sessions: [ChatSession] = []
    func loadSessions() throws -> [ChatSession] { sessions }
    func saveSessions(_ sessions: [ChatSession]) throws { self.sessions = sessions }
    func deleteSession(id: UUID) throws { sessions.removeAll { $0.id == id } }
    func clear() throws { sessions = [] }
}
