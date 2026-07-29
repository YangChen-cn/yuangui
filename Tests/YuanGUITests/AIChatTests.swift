import AppKit
import Combine
import Foundation
import XCTest
@testable import YuanGUI

final class AIChatTests: XCTestCase {
    @MainActor
    private func makeStreamingFixture() -> StreamingChatFixture {
        let defaults = UserDefaults(
            suiteName: "StreamingChatStoreTests-\(UUID().uuidString)"
        )!
        let delay = ManualAsyncDelay()
        let service = ControlledStreamingChatService()
        let chat = ChatStore(
            settings: AISettingsStore(defaults: defaults, secrets: MemorySecretStore()),
            service: service,
            history: MemoryChatHistoryStore(),
            partialReplyDelay: { _ in await delay.wait() }
        )
        return StreamingChatFixture(chat: chat, service: service, delay: delay)
    }

    @MainActor
    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }

    @MainActor
    func testPresentationHookRunsSynchronouslyBeforePublishedStateChanges() {
        let suite = "ChatPresentationHookTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AISettingsStore(defaults: defaults, secrets: MemorySecretStore())
        let chat = ChatStore(settings: settings, history: MemoryChatHistoryStore())
        var targets: [Bool] = []
        var statesObservedByHook: [Bool] = []
        chat.onWillPresentationChange = { target in
            targets.append(target)
            statesObservedByHook.append(chat.isPresented)
        }

        chat.present()
        chat.dismiss()

        XCTAssertEqual(targets, [true, false])
        XCTAssertEqual(statesObservedByHook, [false, true])
        XCTAssertFalse(chat.isPresented)
    }

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

    func testChatUsesExpandedCompletionLimitAndParsesStreamingFragments() throws {
        XCTAssertEqual(AIChatService.maximumCompletionTokens, 4_096)
        XCTAssertEqual(
            try AIChatService.contentFragment(
                fromStreamLine: #"data: {"choices":[{"delta":{"content":"元圭"}}]}"#
            ),
            "元圭"
        )
        XCTAssertEqual(
            try AIChatService.contentFragment(
                fromStreamLine: #"data: {"choices":[{"delta":{"content":"与 VCC"}}]}"#
            ),
            "与 VCC"
        )
        XCTAssertNil(try AIChatService.contentFragment(fromStreamLine: "data: [DONE]"))
        XCTAssertNil(try AIChatService.contentFragment(fromStreamLine: "event: message"))
        XCTAssertNil(try AIChatService.contentFragment(fromStreamLine: ": keep-alive"))
        XCTAssertNil(try AIChatService.contentFragment(fromStreamLine: #"data: {"usage":{"total_tokens":12}}"#))
        XCTAssertEqual(
            try AIChatService.contentFragment(
                fromStreamLine: #"data: {"choices":[{"delta":{"content":[{"type":"text","text":"Hello"},{"type":"text","text":"!"}]}}]}"#
            ),
            "Hello!"
        )
    }

    func testChatParsesArrayBasedNonStreamingContentAndMapsMalformedResponses() throws {
        let data = Data(
            #"{"choices":[{"message":{"content":[{"type":"text","text":"Hello"},{"type":"text","text":" world"}]}}]}"#
                .utf8
        )
        XCTAssertEqual(try AIChatService.responseContent(from: data), "Hello world")
        XCTAssertThrowsError(try AIChatService.responseContent(from: Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? ChatServiceError, .invalidResponse)
        }
    }

    func testModelsEndpointUsesSameCompatibleBasePath() {
        XCTAssertEqual(
            AIModelService.modelsEndpoint(from: "https://example.com/v1")?.absoluteString,
            "https://example.com/v1/models"
        )
        XCTAssertEqual(
            AIModelService.modelsEndpoint(from: "https://example.com/v1/chat/completions")?.absoluteString,
            "https://example.com/v1/models"
        )
        XCTAssertEqual(
            AIModelService.modelsEndpoint(from: "https://example.com/v1/models")?.absoluteString,
            "https://example.com/v1/models"
        )
        XCTAssertNil(AIModelService.modelsEndpoint(from: "ftp://example.com/v1"))
    }

    func testModelServiceReadsSortsAndDeduplicatesModels() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelListURLProtocol.self]
        ModelListURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"data":[{"id":"model-z"},{"id":"model-a"},{"id":"model-a"}]}"#.utf8))
        }
        defer { ModelListURLProtocol.handler = nil }

        let service = AIModelService(session: URLSession(configuration: configuration))
        let models = try await service.models(baseURL: "https://example.com/v1", apiKey: "test-key")

        XCTAssertEqual(models, ["model-a", "model-z"])
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
    func testDefaultPromptFollowsLanguageWithoutOverwritingCustomPrompt() {
        let suite = "AIPromptLanguageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AISettingsStore.defaultPrompt, forKey: "aiSystemPrompt")
        let settings = AISettingsStore(
            defaults: defaults,
            secrets: MemorySecretStore(),
            language: .english
        )

        XCTAssertEqual(settings.systemPrompt, AISettingsStore.englishDefaultPrompt)
        XCTAssertEqual(settings.promptLanguage, .english)

        settings.updateDefaultPromptLanguage(.simplifiedChinese)
        XCTAssertEqual(settings.systemPrompt, AISettingsStore.defaultPrompt)
        XCTAssertEqual(defaults.string(forKey: "aiSystemPrompt"), AISettingsStore.defaultPrompt)

        settings.systemPrompt = "My custom instructions"
        settings.updateDefaultPromptLanguage(.english)
        XCTAssertEqual(settings.systemPrompt, "My custom instructions")
        XCTAssertEqual(settings.promptLanguage, .english)
    }

    func testModeContextUsesTheConfiguredPromptLanguage() {
        let english = AIChatService.modeContext(for: .duo, language: .english)
        let chinese = AIChatService.modeContext(for: .duo, language: .simplifiedChinese)

        XCTAssertTrue(english.hasPrefix("Current desktop companion:"))
        XCTAssertFalse(english.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
        XCTAssertTrue(chinese.hasPrefix("当前桌宠角色："))
    }

    @MainActor
    func testSettingsConnectsAndKeepsManualModelChoice() async {
        let suite = "AIModelSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AISettingsStore(
            defaults: defaults,
            secrets: MemorySecretStore(),
            modelService: StubModelService(models: ["model-a", "model-b"])
        )
        settings.updateBaseURL("https://example.com/v1")
        settings.updateAPIKey("test-key")
        settings.model = "manual-model"

        await settings.connectAndLoadModels()

        XCTAssertEqual(settings.availableModels, ["model-a", "model-b"])
        XCTAssertEqual(settings.model, "manual-model")
        XCTAssertEqual(settings.connectionMessage, "连接成功，读取到 2 个模型")
        XCTAssertFalse(settings.isConnecting)
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
        chat.present()

        await chat.send("第一问", petMode: .duo)
        XCTAssertEqual(chat.latestReply, "第一次回复")
        await chat.send("第二问", petMode: .duo)

        XCTAssertEqual(chat.latestReply, "第二次回复")
        let received = await service.receivedContents()
        XCTAssertEqual(received, [["第一问"], ["第一问", "第一次回复", "第二问"]])
        XCTAssertEqual(chat.sessions.first?.messages.count, 4)
    }

    @MainActor
    func testRapidPartialRepliesAreCoalescedIntoOnePublishedUpdate() async {
        let fixture = makeStreamingFixture()
        var publishedReplies: [String] = []
        let cancellable = fixture.chat.$latestReply
            .compactMap { $0 }
            .sink { publishedReplies.append($0) }
        fixture.chat.present()
        let sendTask = Task { await fixture.chat.send("问题", petMode: .duo) }
        await fixture.service.waitUntilRequested()

        await fixture.service.emit("一")
        await fixture.service.emit("一二")
        await fixture.service.emit("一二三")
        XCTAssertTrue(publishedReplies.isEmpty)

        fixture.delay.resumeNext()
        await waitUntil { fixture.chat.latestReply == "一二三" }
        XCTAssertEqual(publishedReplies, ["一二三"])

        await fixture.service.finish(with: "完整回复")
        await sendTask.value
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testVisibleThrottlePublishesNewestPartialInsteadOfOlderContent() async {
        let fixture = makeStreamingFixture()
        fixture.chat.present()
        let sendTask = Task { await fixture.chat.send("问题", petMode: .duo) }
        await fixture.service.waitUntilRequested()

        await fixture.service.emit("旧内容")
        await fixture.service.emit("最新内容")
        fixture.delay.resumeNext()

        await waitUntil { fixture.chat.latestReply == "最新内容" }
        XCTAssertEqual(fixture.chat.latestReply, "最新内容")
        await fixture.service.finish(with: "最终内容")
        await sendTask.value
    }

    @MainActor
    func testHiddenChatBuffersPartialsWithoutPublishingLatestReply() async {
        let fixture = makeStreamingFixture()
        fixture.chat.present()
        let sendTask = Task { await fixture.chat.send("问题", petMode: .duo) }
        await fixture.service.waitUntilRequested()
        await fixture.service.emit("可见内容")
        fixture.delay.resumeNext()
        await waitUntil { fixture.chat.latestReply == "可见内容" }

        fixture.chat.dismiss()
        await fixture.service.emit("隐藏内容一")
        await fixture.service.emit("隐藏内容二")
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(fixture.chat.latestReply, "可见内容")
        XCTAssertEqual(fixture.delay.waiterCount, 0)
        await fixture.service.finish(with: "最终内容")
        await sendTask.value
    }

    @MainActor
    func testPresentingChatImmediatelyPublishesLatestHiddenPartial() async {
        let fixture = makeStreamingFixture()
        fixture.chat.present()
        let sendTask = Task { await fixture.chat.send("问题", petMode: .duo) }
        await fixture.service.waitUntilRequested()
        fixture.chat.dismiss()
        await fixture.service.emit("隐藏期间的最新内容")

        fixture.chat.present()

        XCTAssertEqual(fixture.chat.latestReply, "隐藏期间的最新内容")
        await fixture.service.finish(with: "最终内容")
        await sendTask.value
    }

    @MainActor
    func testFinalReplyReplacesPendingPartialAndAppendsOneAssistantMessage() async {
        let fixture = makeStreamingFixture()
        var publishedReplies: [String] = []
        let cancellable = fixture.chat.$latestReply
            .compactMap { $0 }
            .sink { publishedReplies.append($0) }
        fixture.chat.present()
        let sendTask = Task { await fixture.chat.send("问题", petMode: .duo) }
        await fixture.service.waitUntilRequested()
        await fixture.service.emit("尚未发布的 partial")

        await fixture.service.finish(with: "唯一完整回复")
        await sendTask.value

        XCTAssertEqual(fixture.chat.latestReply, "唯一完整回复")
        XCTAssertEqual(
            fixture.chat.currentSession?.messages.filter { $0.role == .assistant }.map(\.content),
            ["唯一完整回复"]
        )
        XCTAssertEqual(publishedReplies, ["唯一完整回复"])
        fixture.delay.resumeAll()
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testStreamingFailureClearsResidualPartialBeforePublishingError() async {
        let defaults = UserDefaults(
            suiteName: "FailingStreamingChatStoreTests-\(UUID().uuidString)"
        )!
        let delay = ManualAsyncDelay()
        let chat = ChatStore(
            settings: AISettingsStore(defaults: defaults, secrets: MemorySecretStore()),
            service: FailingStreamingChatService(),
            history: MemoryChatHistoryStore(),
            partialReplyDelay: { _ in await delay.wait() }
        )
        chat.present()

        await chat.send("问题", petMode: .duo)

        XCTAssertNil(chat.latestReply)
        XCTAssertEqual(chat.errorMessage, "测试流式错误")
        delay.resumeAll()
    }

    @MainActor
    func testReopeningDuringDismissCancelsStaleCollapse() async {
        let delay = ManualAsyncDelay()
        let coordinator = ChatPresentationCoordinator { _ in await delay.wait() }
        var collapses = 0
        coordinator.collapseToCompactLayout = { collapses += 1 }

        coordinator.present(reduceMotion: false)
        await waitUntil { coordinator.phase == .presented }
        coordinator.dismiss(reduceMotion: false)
        XCTAssertEqual(coordinator.phase, .dismissing)

        coordinator.present(reduceMotion: false)
        await waitUntil { coordinator.phase == .presented }
        delay.resumeAll()
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(coordinator.phase, .presented)
        XCTAssertTrue(coordinator.keepsExpandedLayout)
        XCTAssertEqual(collapses, 0)
    }

    @MainActor
    func testDismissKeepsExpandedLayoutUntilContentDelayCompletes() async {
        let delay = ManualAsyncDelay()
        let coordinator = ChatPresentationCoordinator { _ in await delay.wait() }
        var events: [String] = []
        coordinator.prepareExpandedLayout = { events.append("expand") }
        coordinator.collapseToCompactLayout = { events.append("collapse") }
        coordinator.setPetChatting = { events.append("chat:\($0)") }

        coordinator.present(reduceMotion: false)
        await waitUntil { coordinator.phase == .presented }
        coordinator.dismiss(reduceMotion: false)

        XCTAssertEqual(coordinator.phase, .dismissing)
        XCTAssertTrue(coordinator.keepsExpandedLayout)
        XCTAssertEqual(events, ["expand", "chat:true"])

        await waitUntil { delay.waiterCount == 1 }
        delay.resumeNext()
        await waitUntil { coordinator.phase == .hidden }
        XCTAssertFalse(coordinator.keepsExpandedLayout)
        XCTAssertEqual(events.prefix(3), ["expand", "chat:true", "collapse"])
        await waitUntil { events.last == "chat:false" }
    }

    @MainActor
    func testOldSessionPartialAndFinalNeverAppearInNewSession() async throws {
        let fixture = makeStreamingFixture()
        fixture.chat.present()
        let sendTask = Task { await fixture.chat.send("原会话问题", petMode: .duo) }
        await fixture.service.waitUntilRequested()
        let originalSessionID = try XCTUnwrap(fixture.chat.currentSessionID)
        await fixture.service.emit("原会话 partial")

        fixture.chat.newSession()
        let newSessionID = try XCTUnwrap(fixture.chat.currentSessionID)
        fixture.delay.resumeAll()
        await fixture.service.finish(with: "原会话最终回复")
        await sendTask.value

        XCTAssertNil(fixture.chat.latestReply)
        XCTAssertTrue(fixture.chat.sessions.first { $0.id == newSessionID }?.messages.isEmpty == true)
        XCTAssertEqual(
            fixture.chat.sessions.first { $0.id == originalSessionID }?.messages.map(\.content),
            ["原会话问题", "原会话最终回复"]
        )
    }

    @MainActor
    func testReduceMotionDismissSkipsNormalAnimationDelay() async {
        let delay = ManualAsyncDelay()
        let coordinator = ChatPresentationCoordinator { _ in await delay.wait() }
        var collapsed = false
        coordinator.collapseToCompactLayout = { collapsed = true }

        coordinator.present(reduceMotion: true)
        await waitUntil { coordinator.phase == .presented }
        coordinator.dismiss(reduceMotion: true)
        await waitUntil { coordinator.phase == .hidden }

        XCTAssertTrue(collapsed)
        XCTAssertEqual(delay.waiterCount, 0)
    }

    @MainActor
    func testReplyReturnsToSessionThatSentRequestAfterSwitchingSessions() async {
        let suite = "ChatSessionOwnershipTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecretStore()
        secrets.value = "test-key"
        let settings = AISettingsStore(defaults: defaults, secrets: secrets)
        let service = SuspendedChatService(reply: "原会话回复")
        let chat = ChatStore(settings: settings, service: service, history: MemoryChatHistoryStore())

        let sendTask = Task { @MainActor in
            await chat.send("原会话问题", petMode: .duo)
        }
        await service.waitUntilRequested()
        let originalSessionID = try! XCTUnwrap(chat.currentSessionID)
        chat.newSession()
        let newSessionID = try! XCTUnwrap(chat.currentSessionID)
        await service.resume()
        await sendTask.value

        let original = chat.sessions.first { $0.id == originalSessionID }
        let current = chat.sessions.first { $0.id == newSessionID }
        XCTAssertEqual(original?.messages.map(\.content), ["原会话问题", "原会话回复"])
        XCTAssertTrue(current?.messages.isEmpty == true)
        XCTAssertNil(chat.latestReply)
    }

    @MainActor
    func testSessionLoadDoesNotRestoreDeletedSessionUsingStaleIndex() async {
        let suite = "ChatSessionLoadRaceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persisted = ChatSession(
            title: "磁盘会话",
            messages: [ChatMessage(role: .assistant, content: "磁盘回复")]
        )
        let loadStarted = expectation(description: "session load started")
        let history = BlockingChatHistoryStore(session: persisted, loadStarted: loadStarted)
        let chat = ChatStore(
            settings: AISettingsStore(defaults: defaults, secrets: MemorySecretStore()),
            service: SequencedChatService(replies: []),
            history: history
        )

        for _ in 0..<100 where !chat.sessions.contains(where: { $0.id == persisted.id }) {
            await Task.yield()
        }
        XCTAssertTrue(chat.sessions.contains(where: { $0.id == persisted.id }))
        chat.selectSession(persisted.id)
        await fulfillment(of: [loadStarted], timeout: 1)
        chat.deleteSession(persisted.id)
        history.resumeLoad()
        for _ in 0..<100 where chat.isLoadingSession {
            await Task.yield()
        }

        XCTAssertFalse(chat.sessions.contains(where: { $0.id == persisted.id }))
    }

    func testChatHistoryFileStorePersistsDeletesAndProtectsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatHistoryFileStore(directoryURL: directory)
        let session = ChatSession(title: "测试", messages: [ChatMessage(role: .user, content: "你好")])

        try store.save(session: session, metadata: [ChatSessionMetadata(session: session)])

        let loaded = try store.loadMetadata().compactMap { try store.loadSession(id: $0.id) }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, session.id)
        XCTAssertEqual(loaded.first?.title, session.title)
        XCTAssertEqual(loaded.first?.messages.map(\.content), ["你好"])
        XCTAssertEqual(loaded.first?.createdAt.timeIntervalSince1970 ?? 0, session.createdAt.timeIntervalSince1970, accuracy: 1)
        let file = directory.appendingPathComponent("Sessions/\(session.id.uuidString).json")
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try store.deleteSession(id: session.id, metadata: [])
        XCTAssertEqual(try store.loadMetadata(), [])
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

@MainActor
private struct StreamingChatFixture {
    let chat: ChatStore
    let service: ControlledStreamingChatService
    let delay: ManualAsyncDelay
}

@MainActor
private final class ManualAsyncDelay {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int { waiters.count }

    func wait() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func resumeNext() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ControlledStreamingChatService: AIChatServicing {
    private var partialHandler: (@MainActor (String) -> Void)?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false
    private var replyContinuation: CheckedContinuation<String, Never>?

    func reply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String {
        await withCheckedContinuation { replyContinuation = $0 }
    }

    func streamReply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode,
        onPartialReply: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        partialHandler = onPartialReply
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { replyContinuation = $0 }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func emit(_ content: String) async {
        guard let partialHandler else { return }
        await partialHandler(content)
    }

    func finish(with reply: String) {
        replyContinuation?.resume(returning: reply)
        replyContinuation = nil
        partialHandler = nil
    }
}

private struct FailingStreamingChatService: AIChatServicing {
    struct Failure: LocalizedError {
        var errorDescription: String? { "测试流式错误" }
    }

    func reply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String {
        throw Failure()
    }

    func streamReply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode,
        onPartialReply: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        await onPartialReply("不应残留的 partial")
        throw Failure()
    }
}

private final class MemorySecretStore: SecretStoring {
    var value: String?
    func read(service: String, account: String) -> String? { value }
    func save(_ value: String, service: String, account: String) throws { self.value = value }
    func delete(service: String, account: String) throws { value = nil }
}

private struct StubModelService: AIModelListing {
    let models: [String]
    func models(baseURL: String, apiKey: String) async throws -> [String] { models }
}

private final class ModelListURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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

private actor SuspendedChatService: AIChatServicing {
    private let response: String
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var replyContinuation: CheckedContinuation<String, Never>?

    init(reply: String) {
        response = reply
    }

    func reply(
        messages: [ChatMessage],
        attachments: [PreparedChatAttachment],
        configuration: AIChatConfiguration,
        petMode: PetMode
    ) async throws -> String {
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { replyContinuation = $0 }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resume() {
        replyContinuation?.resume(returning: response)
        replyContinuation = nil
    }
}

private final class MemoryChatHistoryStore: ChatHistoryStoring {
    var sessions: [ChatSession] = []
    func loadMetadata() throws -> [ChatSessionMetadata] { sessions.map(ChatSessionMetadata.init) }
    func loadSession(id: UUID) throws -> ChatSession? { sessions.first { $0.id == id } }
    func save(session: ChatSession, metadata: [ChatSessionMetadata]) throws {
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
    }
    func deleteSession(id: UUID, metadata: [ChatSessionMetadata]) throws { sessions.removeAll { $0.id == id } }
    func clear() throws { sessions = [] }
}

private final class BlockingChatHistoryStore: ChatHistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let loadRelease = DispatchSemaphore(value: 0)
    private let loadStarted: XCTestExpectation
    private var session: ChatSession?

    init(session: ChatSession, loadStarted: XCTestExpectation) {
        self.session = session
        self.loadStarted = loadStarted
    }

    func loadMetadata() throws -> [ChatSessionMetadata] {
        lock.withLock { session.map { [ChatSessionMetadata(session: $0)] } ?? [] }
    }

    func loadSession(id: UUID) throws -> ChatSession? {
        loadStarted.fulfill()
        loadRelease.wait()
        return lock.withLock { session?.id == id ? session : nil }
    }

    func save(session: ChatSession, metadata: [ChatSessionMetadata]) throws {
        lock.withLock { self.session = session }
    }

    func deleteSession(id: UUID, metadata: [ChatSessionMetadata]) throws {
        lock.withLock {
            if session?.id == id { session = nil }
        }
    }

    func clear() throws {
        lock.withLock { session = nil }
    }

    func resumeLoad() {
        loadRelease.signal()
    }
}
