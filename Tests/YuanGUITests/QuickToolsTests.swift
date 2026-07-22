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

    func testScreenshotTranslationOverlayKeepsExactSelectionFrame() {
        let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let smallSelection = ScreenshotSelection(
            globalRect: CGRect(x: -1435, y: 5, width: 80, height: 30),
            displayID: 7,
            displayFrame: display,
            scale: 2
        )
        XCTAssertEqual(
            ScreenshotTranslationOverlayWindowController.overlayFrame(for: smallSelection),
            smallSelection.globalRect
        )

        let largeSelection = ScreenshotSelection(
            globalRect: CGRect(x: -900, y: 240, width: 420, height: 220),
            displayID: 7,
            displayFrame: display,
            scale: 2
        )
        XCTAssertEqual(
            ScreenshotTranslationOverlayWindowController.overlayFrame(for: largeSelection),
            largeSelection.globalRect
        )
    }

    func testScreenshotTranslationBlocksFollowOCRRegionsAndDistributeFallbackText() throws {
        let regions = [
            OCRTextRegion(text: "第一行", normalizedRect: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1)),
            OCRTextRegion(text: "第二行", normalizedRect: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.1))
        ]
        let aligned = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedText: "First line\nSecond line"
        )
        XCTAssertEqual(aligned.map(\.text), ["First line", "Second line"])
        XCTAssertEqual(aligned[0].normalizedRect.minX, regions[0].normalizedRect.minX)
        XCTAssertEqual(aligned[1].normalizedRect.minX, regions[1].normalizedRect.minX)
        XCTAssertGreaterThanOrEqual(aligned[0].normalizedRect.width, regions[0].normalizedRect.width)
        XCTAssertGreaterThanOrEqual(aligned[1].normalizedRect.width, regions[1].normalizedRect.width)
        XCTAssertEqual(aligned.map(\.backgroundColor), [.white, .white])

        let fallback = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedText: "A translation without matching line breaks"
        )
        XCTAssertEqual(fallback.count, 2)
        XCTAssertEqual(fallback.map(\.text).joined(separator: " "), "A translation without matching line breaks")
        XCTAssertEqual(fallback[0].backgroundColor, regions[0].backgroundColor)
        XCTAssertEqual(fallback[1].backgroundColor, regions[1].backgroundColor)

        let perLine = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedLines: ["Exact first row", "Exact second row"]
        )
        XCTAssertEqual(perLine.map(\.text), ["Exact first row", "Exact second row"])
    }

    @MainActor
    func testTranslationWindowKeepsChosenWidthAndGrowsOnlyVertically() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let short = TranslationWindowLayout.calculate(
            source: "你好",
            translation: "Hello",
            availableFrame: visibleFrame,
            preferredWidth: 510
        )
        let long = TranslationWindowLayout.calculate(
            source: String(repeating: "这是一段需要完整显示的长原文。", count: 80),
            translation: String(repeating: "This is a long translated paragraph that should expand the window. ", count: 80),
            availableFrame: visibleFrame,
            preferredWidth: 510
        )

        XCTAssertEqual(short.contentSize.width, 510)
        XCTAssertEqual(long.contentSize.width, short.contentSize.width)
        XCTAssertGreaterThan(long.contentSize.height, short.contentSize.height)
        XCTAssertLessThanOrEqual(long.contentSize.width, visibleFrame.width - 32)
        XCTAssertLessThanOrEqual(long.contentSize.height, visibleFrame.height - 32)
        XCTAssertGreaterThan(long.sourceHeight, short.sourceHeight)
        XCTAssertGreaterThan(long.resultHeight, short.resultHeight)
    }

    func testScreenshotTranslationToolbarChoosesAvailableOutsideEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let toolbarSize = CGSize(width: 160, height: 40)
        let middle = ScreenshotTranslationOverlayWindowController.toolbarFrame(
            for: CGRect(x: 100, y: 200, width: 500, height: 300),
            toolbarSize: toolbarSize,
            visibleFrame: screen
        )
        XCTAssertEqual(middle.minY, 506)

        let nearTop = ScreenshotTranslationOverlayWindowController.toolbarFrame(
            for: CGRect(x: 100, y: 390, width: 500, height: 300),
            toolbarSize: toolbarSize,
            visibleFrame: screen
        )
        XCTAssertEqual(nearTop.maxY, 384)
        XCTAssertFalse(nearTop.intersects(CGRect(x: 100, y: 390, width: 500, height: 300)))
    }

    func testScreenshotTranslationComparisonUsesEqualSizedSideBySideFrames() {
        let frames = ScreenshotTranslationOverlayWindowController.comparisonFrames(
            for: CGRect(x: 300, y: 180, width: 360, height: 220),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
        )
        XCTAssertEqual(frames.original.size, frames.translated.size)
        XCTAssertEqual(frames.original.maxX + 12, frames.translated.minX)
        XCTAssertEqual(frames.original.minY, frames.translated.minY)

        let oversized = ScreenshotTranslationOverlayWindowController.comparisonFrames(
            for: CGRect(x: 20, y: 20, width: 1_100, height: 650),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
        )
        XCTAssertEqual(oversized.original.size, oversized.translated.size)
        XCTAssertFalse(oversized.original.intersects(oversized.translated))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1_200, height: 800).contains(oversized.original))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1_200, height: 800).contains(oversized.translated))
    }

    @MainActor
    func testScreenshotTranslationDisplayBlocksFitEveryLineWithoutOverlapOrTruncation() {
        let blocks = [
            ScreenshotTranslationBlock(
                id: 0,
                normalizedRect: CGRect(x: 0.05, y: 0.75, width: 0.7, height: 0.04),
                text: "A translated line that needs more vertical room",
                backgroundColor: .white
            ),
            ScreenshotTranslationBlock(
                id: 1,
                normalizedRect: CGRect(x: 0.05, y: 0.68, width: 0.7, height: 0.04),
                text: "The following line must remain separate and readable",
                backgroundColor: .white
            )
        ]
        let display = ScreenshotTranslationOverlayWindowController.displayBlocks(
            from: blocks,
            in: CGSize(width: 500, height: 260)
        )

        XCTAssertEqual(display.count, 2)
        for block in display {
            let font = NSFont.systemFont(ofSize: block.fontSize, weight: .regular)
            let measuredWidth = ceil((block.text as NSString).size(withAttributes: [.font: font]).width)
            let measuredHeight = ceil(font.ascender - font.descender + font.leading)
            XCTAssertLessThanOrEqual(measuredWidth, block.frame.width - 4)
            XCTAssertLessThanOrEqual(measuredHeight, block.frame.height - 2)
            XCTAssertGreaterThanOrEqual(block.fontSize, 5)
        }
        let sorted = display.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertLessThanOrEqual(sorted[0].frame.maxY + 1, sorted[1].frame.minY)
    }

    @MainActor
    func testScreenshotTranslationUsesNearbyWhitespaceForLargerReadableText() {
        let target = ScreenshotTranslationBlock(
            id: 1,
            normalizedRect: CGRect(x: 0.1, y: 0.48, width: 0.6, height: 0.04),
            text: "Readable translation",
            backgroundColor: .white
        )
        let isolated = ScreenshotTranslationOverlayWindowController.displayBlocks(
            from: [target],
            in: CGSize(width: 500, height: 260)
        )[0]
        let dense = ScreenshotTranslationOverlayWindowController.displayBlocks(
            from: [
                ScreenshotTranslationBlock(
                    id: 0,
                    normalizedRect: CGRect(x: 0.1, y: 0.53, width: 0.6, height: 0.04),
                    text: "Nearby line above",
                    backgroundColor: .white
                ),
                target,
                ScreenshotTranslationBlock(
                    id: 2,
                    normalizedRect: CGRect(x: 0.1, y: 0.43, width: 0.6, height: 0.04),
                    text: "Nearby line below",
                    backgroundColor: .white
                )
            ],
            in: CGSize(width: 500, height: 260)
        ).first { $0.id == target.id }!

        XCTAssertGreaterThan(isolated.frame.height, dense.frame.height)
        XCTAssertGreaterThan(isolated.fontSize, dense.fontSize)
    }

    @MainActor
    func testScreenshotTranslationSeparatesAlreadyOverlappingOCRRows() {
        let blocks = [
            ScreenshotTranslationBlock(
                id: 0,
                normalizedRect: CGRect(x: 0.08, y: 0.52, width: 0.78, height: 0.08),
                text: "First translated row remains readable",
                backgroundColor: .white
            ),
            ScreenshotTranslationBlock(
                id: 1,
                normalizedRect: CGRect(x: 0.08, y: 0.47, width: 0.78, height: 0.08),
                text: "Second translated row cannot overlap it",
                backgroundColor: .white
            ),
            ScreenshotTranslationBlock(
                id: 2,
                normalizedRect: CGRect(x: 0.08, y: 0.42, width: 0.78, height: 0.08),
                text: "Third translated row also gets its own slot",
                backgroundColor: .white
            )
        ]
        let display = ScreenshotTranslationOverlayWindowController.displayBlocks(
            from: blocks,
            in: CGSize(width: 720, height: 420)
        ).sorted { $0.frame.minY < $1.frame.minY }

        XCTAssertEqual(display.count, 3)
        for pair in zip(display, display.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.frame.maxY + 0.5, pair.1.frame.minY)
            XCTAssertFalse(pair.0.frame.intersects(pair.1.frame))
        }
    }

    @MainActor
    func testScreenshotShortcutTranslationPreservesOneResultPerOCRLine() async {
        let snapshot = TranslationTargetSnapshot(
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: "截图 OCR 覆盖",
            element: AXUIElementCreateSystemWide(),
            originalText: "第一行\n第二行",
            fullValue: nil,
            selectedRange: nil,
            role: nil,
            canReplace: false
        )
        let shortcut = StubShortcutTranslationService()
        let store = TranslationEditorStore(
            snapshot: snapshot,
            nonChineseTarget: .simplifiedChinese,
            chineseTarget: .english,
            engine: .systemShortcut,
            onlineConfiguration: nil,
            shortcutService: shortcut,
            onReplaced: {}
        )

        await store.performShortcutLineTranslations(sourceLines: ["第一行", "第二行"])

        XCTAssertEqual(shortcut.callCount, 1)
        XCTAssertFalse(shortcut.lastInput.contains("YGUI"))
        XCTAssertEqual(store.translatedLines, ["First row", "Second row"])
        XCTAssertEqual(store.translatedText, "First row\nSecond row")
    }

    func testScreenshotTranslationAlignerFallsBackToPunctuationWhenMarkersAreLost() {
        let source = ["第一条内容比较短。", "第二条内容明显更长一些。", "第三条。"]
        let aligned = ScreenshotTranslationLineAligner.align(
            "The first item is short. The second item contains noticeably more detail. The third item is brief.",
            to: source
        )

        XCTAssertEqual(aligned.count, source.count)
        XCTAssertEqual(aligned.joined(separator: " "), "The first item is short. The second item contains noticeably more detail. The third item is brief.")
        XCTAssertTrue(aligned[0].hasSuffix("."))
        XCTAssertTrue(aligned[1].hasSuffix("."))
    }

    func testScreenshotTranslationOverlayStaysOnCurrentDesktop() {
        let behavior = ScreenshotTranslationOverlayWindowController.panelCollectionBehavior
        XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.moveToActiveSpace))
    }

    func testTranslationTextFormatterRestoresFlattenedListLineBreaksWithoutSplittingNames() {
        let flattened = "说明如下： · 保留完整背景。 · 只擦除文字区域。 · 深色背景使用白字。"
        XCTAssertEqual(
            TranslationTextFormatter.addingSemanticLineBreaks(flattened),
            "说明如下：\n• 保留完整背景。\n• 只擦除文字区域。\n• 深色背景使用白字。"
        )
        XCTAssertEqual(
            TranslationTextFormatter.addingSemanticLineBreaks("周杰伦 · 陶喆"),
            "周杰伦 · 陶喆"
        )
        XCTAssertEqual(
            TranslationTextFormatter.addingSemanticLineBreaks("First • Second • Third"),
            "First\n• Second\n• Third"
        )
    }

    @MainActor
    func testTranslationEditorAutomaticallyFormatsFlattenedSelectedText() {
        let snapshot = TranslationTargetSnapshot(
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: "浏览器",
            element: AXUIElementCreateSystemWide(),
            originalText: "说明： · 第一项。 · 第二项。 · 第三项。",
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

        XCTAssertEqual(store.originalSourceText, snapshot.originalText)
        XCTAssertEqual(store.editableSourceText, "说明：\n• 第一项。\n• 第二项。\n• 第三项。")
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
    func testClipboardSelectionWaitsForDelayedBrowserCopy() async {
        let pasteboard = NSPasteboard(name: .init("SelectionCopyTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            pasteboard.clearContents()
            pasteboard.setString("  网页选中文字  ", forType: .string)
        }

        let selected = await AccessibilitySelectedTextProvider.waitForCopiedString(
            from: pasteboard,
            after: changeCount,
            attempts: 20
        )
        XCTAssertEqual(selected, "网页选中文字")
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
        XCTAssertFalse(store.screenshotTranslationOverlayEnabled)
        let replacement = HotKeyBinding(keyCode: 8, modifiers: [.command, .option], keyLabel: "C")
        store.saveHotKey(replacement, for: .regionScreenshot)
        store.setChineseTarget(.japanese)
        store.setTranslationEngine(.onlineAI)
        store.setScreenshotTranslationOverlayEnabled(true)

        let reloaded = QuickToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.screenshotHotKey, replacement)
        XCTAssertEqual(reloaded.chineseTarget, .japanese)
        XCTAssertEqual(reloaded.translationEngine, .onlineAI)
        XCTAssertTrue(reloaded.screenshotTranslationOverlayEnabled)
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

private final class StubShortcutTranslationService: SystemShortcutTranslationServicing {
    private(set) var callCount = 0
    private(set) var lastInput = ""

    func translate(_ text: String, target: QuickToolLanguage) async throws -> String {
        callCount += 1
        lastInput = text
        return text
            .replacingOccurrences(of: "第一行", with: "First row")
            .replacingOccurrences(of: "第二行", with: "Second row")
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
