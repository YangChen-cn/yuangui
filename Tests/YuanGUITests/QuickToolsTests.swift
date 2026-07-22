import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ImageIO
import XCTest
@testable import YuanGUI

final class QuickToolsTests: XCTestCase {
    func testHotKeyValidationAndRoundTrip() throws {
        XCTAssertNil(HotKeyBinding.screenshotDefault.validationMessage)
        XCTAssertEqual(HotKeyBinding.screenshotDefault.displayText, "⌃A")
        XCTAssertEqual(HotKeyBinding.screenshotTranslationDefault.displayText, "⌃⇧A")
        XCTAssertEqual(HotKeyBinding.translationDefault.displayText, "⌃Z")

        let invalid = HotKeyBinding(keyCode: 0, modifiers: [.shift], keyLabel: "A")
        XCTAssertNotNil(invalid.validationMessage)

        let data = try JSONEncoder().encode(HotKeyBinding.translationDefault)
        XCTAssertEqual(try JSONDecoder().decode(HotKeyBinding.self, from: data), .translationDefault)
    }

    func testScreenshotSelectionConvertsGlobalCoordinatesToDisplayCoordinates() {
        let selection = ScreenshotSelection(
            globalRect: CGRect(x: -1200, y: 180, width: 300, height: 220),
            displayID: 7,
            displayFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900),
            scale: 2
        )
        XCTAssertEqual(selection.displayLocalSourceRect, CGRect(x: 240, y: 500, width: 300, height: 220))
    }

    func testVisionOCRHandlesBlankScreenshot() async throws {
        let text = try await VisionOCRService().recognizeText(in: makeImage(width: 120, height: 80))
        XCTAssertTrue(text.isEmpty)
    }

    @MainActor
    func testScreenshotEditorUndoAndRedo() throws {
        let store = ScreenshotEditorStore(image: try makeImage(width: 80, height: 60))
        store.beginDrawing(at: CGPoint(x: 10, y: 10))
        store.continueDrawing(to: CGPoint(x: 30, y: 30))
        store.endDrawing(at: CGPoint(x: 40, y: 40))
        XCTAssertEqual(store.annotations.count, 1)
        XCTAssertTrue(store.canUndo)

        store.undo()
        XCTAssertTrue(store.annotations.isEmpty)
        XCTAssertTrue(store.canRedo)

        store.redo()
        XCTAssertEqual(store.annotations.count, 1)
    }

    func testRendererKeepsOriginalPixelSize() throws {
        let image = try makeImage(width: 96, height: 64)
        let annotation = ScreenshotAnnotation.line(
            id: UUID(),
            start: CGPoint(x: 5, y: 5),
            end: CGPoint(x: 80, y: 50),
            style: AnnotationStyle(color: .systemRed, lineWidth: 4, fontSize: 20),
            arrow: true
        )
        let data = try ScreenshotRenderer.pngData(image: image, annotations: [annotation])
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let rendered = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("Unable to decode rendered PNG")
        }
        XCTAssertEqual(rendered.width, 96)
        XCTAssertEqual(rendered.height, 64)
    }

    func testScreenshotSaveAddsCollisionSuffix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-QuickToolsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ScreenshotOutputService()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try service.savePNG(Data([1, 2, 3]), directoryPath: directory.path, now: date)
        let second = try service.savePNG(Data([4, 5, 6]), directoryPath: directory.path, now: date)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.deletingPathExtension().lastPathComponent.hasSuffix(" 2"))
    }

    func testAccessibilitySubstringUsesUTF16Ranges() {
        let value = "A😀中文B"
        XCTAssertEqual(
            AccessibilitySelectedTextProvider.substring(value, range: CFRange(location: 1, length: 4)),
            "😀中文"
        )
        XCTAssertNil(AccessibilitySelectedTextProvider.substring(value, range: CFRange(location: 99, length: 1)))
    }

    @MainActor
    func testQuickToolSettingsUseIsolatedDefaults() {
        let suiteName = "QuickToolsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = QuickToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(store.screenshotHotKey, .screenshotDefault)
        XCTAssertEqual(store.screenshotTranslationHotKey, .screenshotTranslationDefault)
        XCTAssertEqual(store.translationHotKey, .translationDefault)
        let replacement = HotKeyBinding(keyCode: 8, modifiers: [.command, .option], keyLabel: "C")
        store.saveHotKey(replacement, for: .regionScreenshot)
        store.setChineseTarget(.japanese)
        store.setTranslationEngine(.onlineAI)

        let reloaded = QuickToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.screenshotHotKey, replacement)
        XCTAssertEqual(reloaded.chineseTarget, .japanese)
        XCTAssertEqual(reloaded.translationEngine, .onlineAI)
    }

    @MainActor
    func testQuickToolSettingsMigratePreviousDefaultHotKeys() throws {
        let suiteName = "QuickToolsMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(HotKeyBinding(
            keyCode: UInt32(kVK_ANSI_A), modifiers: [.control, .shift], keyLabel: "A"
        )), forKey: "quickTools.screenshotHotKey")
        defaults.set(try JSONEncoder().encode(HotKeyBinding(
            keyCode: UInt32(kVK_ANSI_T), modifiers: [.control, .shift], keyLabel: "T"
        )), forKey: "quickTools.translationHotKey")

        let store = QuickToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(store.screenshotHotKey, .screenshotDefault)
        XCTAssertEqual(store.screenshotTranslationHotKey, .screenshotTranslationDefault)
        XCTAssertEqual(store.translationHotKey, .translationDefault)
    }

    @MainActor
    func testManualTranslationInputAutomaticallyChoosesDirectionUntilUserOverridesIt() {
        let snapshot = TranslationTargetSnapshot(
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: "手动输入",
            element: AXUIElementCreateSystemWide(),
            originalText: "",
            fullValue: nil,
            selectedRange: nil,
            role: nil,
            canReplace: false
        )
        let store = TranslationEditorStore(
            snapshot: snapshot,
            nonChineseTarget: .simplifiedChinese,
            chineseTarget: .english,
            engine: .systemShortcut,
            onlineConfiguration: nil,
            onReplaced: {}
        )

        store.updateEditableSourceText("这是一段中文")
        XCTAssertEqual(store.targetLanguage, .english)
        store.updateEditableSourceText("hello world")
        XCTAssertEqual(store.targetLanguage, .simplifiedChinese)
        store.requestTargetLanguage(.japanese)
        store.updateEditableSourceText("继续输入中文")
        XCTAssertEqual(store.targetLanguage, .japanese)
        XCTAssertEqual(store.replacementHint, "手动输入模式")
    }

    func testOnlineTranslationUsesConfiguredCompatibleAPI() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var receivedRequest: URLRequest?
        TranslationURLProtocol.handler = { request in
            receivedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"choices":[{"message":{"content":"And detect conflicts"}}]}"#.utf8))
        }
        defer {
            TranslationURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let result = try await OnlineTranslationService(session: session).translate(
            "并检测冲突",
            target: .english,
            configuration: AITranslationConfiguration(
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "test-key"
            )
        )

        XCTAssertEqual(result, "And detect conflicts")
        XCTAssertEqual(receivedRequest?.url?.path, "/v1/chat/completions")
        XCTAssertEqual(receivedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testSystemShortcutTranslationPayloadUsesYuanGUIDictionaryProtocol() throws {
        let data = try SystemShortcutTranslationService.inputData(text: "并检测冲突", target: .english)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(payload["detectFrom"], "")
        XCTAssertEqual(payload["detectTo"], "en_US")
        XCTAssertEqual(payload["text"], "并检测冲突")
        XCTAssertEqual(SystemShortcutTranslationService.installURL?.lastPathComponent, "YuanGUI.Translate.shortcut")
    }

    func testShortcutInstallerFindsPackagedResourceWithoutDeveloperBuildPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-PackagedResources-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("YuanGUI_YuanGUI.bundle", isDirectory: true)
        let shortcut = bundle.appendingPathComponent("YuanGUI.Translate.shortcut")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: shortcut)

        XCTAssertEqual(
            SystemShortcutTranslationService.installURL(resourceRoots: [root]),
            shortcut
        )
        XCTAssertNil(SystemShortcutTranslationService.installURL(resourceRoots: [root.appendingPathComponent("missing")]))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ScreenshotOutputError.contextCreationFailed }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw ScreenshotOutputError.imageCreationFailed }
        return image
    }
}

private final class TranslationURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
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
