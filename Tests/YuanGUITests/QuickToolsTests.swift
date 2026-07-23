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
            OCRTextRegion(text: "第一行", normalizedRect: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1), paragraphIndex: 0),
            OCRTextRegion(text: "第二行", normalizedRect: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.1), paragraphIndex: 1)
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

    @MainActor
    func testTranslationWindowDoesNotReserveBlankHeightFromMismatchedResultFont() {
        let translation = Array(repeating: "• The translated sentence should fit its measured body text height.", count: 10)
            .joined(separator: "\n")
        let layout = TranslationWindowLayout.calculate(
            source: "这是一段用于验证窗口高度的原文。",
            translation: translation,
            availableFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            preferredWidth: 880
        )
        let measured = (translation as NSString).boundingRect(
            with: CGSize(width: 812, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )

        XCTAssertEqual(layout.resultHeight, max(68, ceil(measured.height) + 20), accuracy: 1)
    }

    @MainActor
    func testShowingTranslationEditorClosesPreviousWindow() {
        let suiteName = "TranslationWindowSingletonTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = QuickToolsController(settings: QuickToolsSettingsStore(defaults: defaults))
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

        let first = controller.showTranslationEditor(snapshot: snapshot)
        XCTAssertTrue(first.isVisible)
        let second = controller.showTranslationEditor(snapshot: snapshot)

        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(second.isVisible)
        second.close()
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

        let crowded = ScreenshotTranslationOverlayWindowController.toolbarFrame(
            for: CGRect(x: 40, y: 5, width: 900, height: 690),
            toolbarSize: toolbarSize,
            visibleFrame: screen
        )
        XCTAssertFalse(crowded.intersects(CGRect(x: 40, y: 5, width: 900, height: 690)))
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
    func testScreenshotTranslationDisplayBlocksKeepHorizontalAnchorsAndUseSevenPointFloor() {
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
        for (index, block) in display.enumerated() {
            let anchor = ScreenshotTranslationOverlayView.displayRect(
                for: blocks[index].normalizedRect,
                in: CGSize(width: 500, height: 260)
            )
            XCTAssertEqual(block.frame.minX, anchor.minX, accuracy: 0.0001)
            XCTAssertEqual(block.frame.width, anchor.width, accuracy: 0.0001)
            XCTAssertTrue(block.frame.intersects(anchor))
            XCTAssertGreaterThanOrEqual(
                block.fontSize,
                ScreenshotTranslationLayoutEngine.minimumInPlaceFontSize
            )
            XCTAssertTrue(ScreenshotTranslationLayoutEngine.textFits(block))
            XCTAssertFalse(block.usesOverflowCard)
        }
    }

    @MainActor
    func testScreenshotTranslationUsesSafeNearbyWhitespaceForLargerText() {
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

        XCTAssertEqual(isolated.frame.minX, dense.frame.minX)
        XCTAssertEqual(isolated.frame.width, dense.frame.width)
        XCTAssertGreaterThan(isolated.frame.height, dense.frame.height)
        XCTAssertGreaterThan(isolated.fontSize, dense.fontSize)
    }

    @MainActor
    func testScreenshotTranslationSeparatesOverlappingRowsWithoutHorizontalDrift() {
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
        for block in display {
            XCTAssertEqual(block.frame.minX, 57.6, accuracy: 0.0001)
            XCTAssertEqual(block.frame.width, 561.6, accuracy: 0.0001)
        }
        for pair in zip(display, display.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.frame.maxY, pair.1.frame.minY)
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

    func testScreenshotTranslationAlignerUsesStableInternalIndexesWithoutLeakingThem() {
        let source = ["First source sentence", "Second source sentence", "Star"]
        let combined = ScreenshotTranslationLineAligner.combinedText(for: source)
        XCTAssertTrue(combined.contains("[[0000]]"))
        let aligned = ScreenshotTranslationLineAligner.align(
            "[[0002]] 星标\n[[0000]] 第一条译文\n[[0001]] 第二条译文",
            to: source
        )

        XCTAssertEqual(aligned, ["第一条译文", "第二条译文", "星标"])
        XCTAssertFalse(aligned.joined().contains("[["))
        XCTAssertFalse(aligned.joined().contains("YGUI"))
    }

    func testSemanticSentenceTranslationCannotAttachDescriptionToTrailingControl() throws {
        let regions = OCRLayoutAnalyzer.organize([
            OCRTextRegion(text: "koala73/worldmonitor", normalizedRect: CGRect(x: 0.06, y: 0.82, width: 0.25, height: 0.04)),
            OCRTextRegion(text: "Star", normalizedRect: CGRect(x: 0.84, y: 0.82, width: 0.08, height: 0.04)),
            OCRTextRegion(text: "Real-time global intelligence dashboard and infrastructure tracking.", normalizedRect: CGRect(x: 0.06, y: 0.72, width: 0.68, height: 0.05)),
            OCRTextRegion(text: "TypeScript 68.3k", normalizedRect: CGRect(x: 0.06, y: 0.63, width: 0.22, height: 0.04))
        ]).regions
        let sentences = ScreenshotTranslationOverlayWindowController.translatableSentences(regions: regions)
        let descriptionIndex = try XCTUnwrap(sentences.firstIndex { $0.hasPrefix("Real-time") })
        let translated = sentences.indices.map { "translation-\($0)" }
        let blocks = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedLines: translated
        )
        let descriptionBlock = try XCTUnwrap(blocks.first { $0.text == "translation-\(descriptionIndex)" })

        XCTAssertEqual(descriptionBlock.normalizedRect.minX, 0.06, accuracy: 0.0001)
        XCTAssertEqual(descriptionBlock.normalizedRect.width, 0.68, accuracy: 0.0001)
        XCTAssertLessThan(descriptionBlock.normalizedRect.maxX, 0.84)
    }

    func testScreenshotTranslationWindowScalingKeepsAspectRatioAndVisibleBounds() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let original = CGRect(x: 300, y: 240, width: 500, height: 250)
        let enlarged = ScreenshotTranslationOverlayWindowController.scaledFrame(
            for: original,
            by: 1.22,
            visibleFrame: visible
        )

        XCTAssertGreaterThan(enlarged.width, original.width)
        XCTAssertEqual(enlarged.width / enlarged.height, original.width / original.height, accuracy: 0.0001)
        XCTAssertTrue(visible.contains(enlarged))
    }

    func testOCRLayoutAnalyzerDeduplicatesAndAssignsStableReadingOrder() {
        let regions = [
            OCRTextRegion(
                text: "Second line",
                normalizedRect: CGRect(x: 0.1, y: 0.60, width: 0.45, height: 0.05),
                confidence: 0.92
            ),
            OCRTextRegion(
                text: "First line",
                normalizedRect: CGRect(x: 0.1, y: 0.72, width: 0.45, height: 0.05),
                confidence: 0.96
            ),
            OCRTextRegion(
                text: "First line",
                normalizedRect: CGRect(x: 0.102, y: 0.721, width: 0.448, height: 0.049),
                confidence: 0.61
            ),
            OCRTextRegion(
                text: "Footer",
                normalizedRect: CGRect(x: 0.65, y: 0.12, width: 0.2, height: 0.04),
                confidence: 0.88
            )
        ]

        let recognition = OCRLayoutAnalyzer.organize(regions)

        XCTAssertEqual(recognition.regions.map(\.text), ["First line", "Second line", "Footer"])
        XCTAssertEqual(recognition.regions.map(\.readingOrder), [0, 1, 2])
        XCTAssertLessThan(recognition.regions[0].paragraphIndex, recognition.regions[2].paragraphIndex)
    }

    func testOCRLayoutAnalyzerRecognizesColumnsTitlesListsAndBaselines() {
        let regions = [
            OCRTextRegion(text: "Document title", normalizedRect: CGRect(x: 0.08, y: 0.9, width: 0.84, height: 0.07), estimatedFontScale: 0.07),
            OCRTextRegion(text: "Left one", normalizedRect: CGRect(x: 0.08, y: 0.72, width: 0.28, height: 0.03)),
            OCRTextRegion(text: "• Left two", normalizedRect: CGRect(x: 0.08, y: 0.62, width: 0.28, height: 0.03)),
            OCRTextRegion(text: "Right one", normalizedRect: CGRect(x: 0.62, y: 0.72, width: 0.28, height: 0.03)),
            OCRTextRegion(text: "Right two", normalizedRect: CGRect(x: 0.62, y: 0.62, width: 0.28, height: 0.03))
        ]

        let result = OCRLayoutAnalyzer.organize(regions).regions

        XCTAssertEqual(result.first?.role, .title)
        XCTAssertEqual(result.filter { $0.text.hasPrefix("Left") || $0.text.hasPrefix("•") }.map(\.columnIndex), [0, 0])
        XCTAssertEqual(
            result.filter { $0.text.hasPrefix("Right") }.map(\.columnIndex),
            [1, 1],
            "\(result.map { ($0.text, $0.columnIndex) })"
        )
        XCTAssertEqual(result.first { $0.text.hasPrefix("•") }?.role, .listItem)
        XCTAssertEqual(result.first { $0.text == "Left one" }?.baseline ?? -1, 0.72, accuracy: 0.0001)
    }

    func testOCRLayoutAnalyzerSeparatesDistantControlsOnTheSameVisualRow() {
        let result = OCRLayoutAnalyzer.organize([
            OCRTextRegion(
                text: "ruvnet/RuView",
                normalizedRect: CGRect(x: 0.06, y: 0.78, width: 0.22, height: 0.05)
            ),
            OCRTextRegion(
                text: "Star",
                normalizedRect: CGRect(x: 0.82, y: 0.78, width: 0.10, height: 0.05)
            ),
            OCRTextRegion(
                text: "RuView turns commodity WiFi signals into real-time intelligence",
                normalizedRect: CGRect(x: 0.06, y: 0.67, width: 0.68, height: 0.05)
            )
        ]).regions

        let repository = result.first { $0.text == "ruvnet/RuView" }
        let control = result.first { $0.text == "Star" }
        let description = result.first { $0.text.hasPrefix("RuView turns") }
        XCTAssertNotEqual(repository?.paragraphIndex, control?.paragraphIndex)
        XCTAssertNotEqual(control?.paragraphIndex, description?.paragraphIndex)
    }

    func testOCRLayoutAnalyzerDoesNotTreatRepeatedTrailingControlsAsASecondColumn() {
        let result = OCRLayoutAnalyzer.organize([
            OCRTextRegion(text: "koala73/worldmonitor", normalizedRect: CGRect(x: 0.06, y: 0.82, width: 0.25, height: 0.04)),
            OCRTextRegion(text: "Star", normalizedRect: CGRect(x: 0.84, y: 0.82, width: 0.08, height: 0.04)),
            OCRTextRegion(text: "Real-time global intelligence dashboard and infrastructure tracking", normalizedRect: CGRect(x: 0.06, y: 0.72, width: 0.68, height: 0.05)),
            OCRTextRegion(text: "TypeScript 68.3k", normalizedRect: CGRect(x: 0.06, y: 0.63, width: 0.22, height: 0.04)),
            OCRTextRegion(text: "ruvnet/RuView", normalizedRect: CGRect(x: 0.06, y: 0.45, width: 0.22, height: 0.04)),
            OCRTextRegion(text: "Star", normalizedRect: CGRect(x: 0.84, y: 0.45, width: 0.08, height: 0.04)),
            OCRTextRegion(text: "RuView turns commodity WiFi signals into real-time spatial intelligence", normalizedRect: CGRect(x: 0.06, y: 0.35, width: 0.70, height: 0.05)),
            OCRTextRegion(text: "Rust 83.4k", normalizedRect: CGRect(x: 0.06, y: 0.26, width: 0.18, height: 0.04))
        ]).regions

        XCTAssertEqual(Set(result.map(\.columnIndex)), [0], "Trailing buttons must stay in row reading order")
        let firstDescription = try? XCTUnwrap(result.first { $0.text.hasPrefix("Real-time") })
        XCTAssertEqual(firstDescription?.columnIndex, 0)
    }

    func testScreenshotTranslationBatchesSemanticSentencesAndProtectsURLs() {
        let regions = [
            OCRTextRegion(text: "First visual line", normalizedRect: CGRect(x: 0.1, y: 0.75, width: 0.5, height: 0.05), paragraphIndex: 0, readingOrder: 0),
            OCRTextRegion(text: "continues here", normalizedRect: CGRect(x: 0.1, y: 0.68, width: 0.5, height: 0.05), paragraphIndex: 0, readingOrder: 1),
            OCRTextRegion(text: "https://example.com", normalizedRect: CGRect(x: 0.1, y: 0.55, width: 0.5, height: 0.05), paragraphIndex: 1, readingOrder: 2),
            OCRTextRegion(text: "Second paragraph", normalizedRect: CGRect(x: 0.1, y: 0.42, width: 0.5, height: 0.05), paragraphIndex: 2, readingOrder: 3)
        ]

        XCTAssertEqual(
            ScreenshotTranslationOverlayWindowController.translatableParagraphs(regions: regions),
            ["First visual line continues here", "Second paragraph"]
        )
        let blocks = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedLines: ["第一行译文继续", "第二段译文"]
        )
        XCTAssertEqual(blocks.count, 2)
        XCTAssertFalse(blocks.contains { $0.text.contains("example.com") })
        XCTAssertEqual(blocks.map(\.text), ["第一行译文继续", "第二段译文"])
        let firstSentenceRect = regions[0].normalizedRect.union(regions[1].normalizedRect)
        XCTAssertEqual(blocks.map(\.normalizedRect), [
            firstSentenceRect,
            regions[3].normalizedRect
        ])
    }

    func testWrappedVisualLinesBecomeOneSemanticSentenceAnchor() {
        let regions = [
            OCRTextRegion(
                text: "我会先执行",
                normalizedRect: CGRect(x: 0.08, y: 0.72, width: 0.42, height: 0.05),
                paragraphIndex: 0,
                readingOrder: 0
            ),
            OCRTextRegion(
                text: "swift test，再构建应用。",
                normalizedRect: CGRect(x: 0.08, y: 0.65, width: 0.58, height: 0.05),
                paragraphIndex: 0,
                readingOrder: 1
            )
        ]

        XCTAssertEqual(
            ScreenshotTranslationOverlayWindowController.translatableParagraphs(regions: regions),
            ["我会先执行 swift test，再构建应用。"]
        )
        let blocks = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedLines: ["I will run swift test first, then build the app."]
        )
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].text, "I will run swift test first, then build the app.")
        XCTAssertEqual(blocks[0].normalizedRect, regions[0].normalizedRect.union(regions[1].normalizedRect))
    }

    func testScreenshotTranslationKeepsVisualLineBreaksWhileBatchingAndSkipsProtectedRows() {
        let regions = [
            OCRTextRegion(text: "Main changes:", normalizedRect: CGRect(x: 0.05, y: 0.82, width: 0.5, height: 0.05), paragraphIndex: 0, readingOrder: 0),
            OCRTextRegion(text: "• First item", normalizedRect: CGRect(x: 0.08, y: 0.72, width: 0.6, height: 0.05), paragraphIndex: 0, readingOrder: 1, role: .listItem),
            OCRTextRegion(text: "https://example.com", normalizedRect: CGRect(x: 0.08, y: 0.62, width: 0.5, height: 0.04), paragraphIndex: 0, readingOrder: 2, role: .protectedContent),
            OCRTextRegion(text: "• Second item", normalizedRect: CGRect(x: 0.08, y: 0.52, width: 0.6, height: 0.05), paragraphIndex: 0, readingOrder: 3, role: .listItem)
        ]

        XCTAssertEqual(
            ScreenshotTranslationOverlayWindowController.translatableVisualLines(regions: regions),
            ["Main changes:", "• First item", "• Second item"]
        )

        let blocks = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: regions,
            translatedLines: ["主要修改：", "• 第一项", "• 第二项"]
        )
        XCTAssertEqual(blocks.map(\.text), ["主要修改：", "• 第一项", "• 第二项"])
        XCTAssertEqual(blocks.map(\.normalizedRect.minY), [0.82, 0.72, 0.52])
        XCTAssertFalse(blocks.contains { $0.text.contains("example.com") })
    }

    func testMixedURLRowsTranslateWhileStandaloneURLsRemainProtected() {
        let mixed = OCRTextRegion(
            text: "For more information, visit https://example.com/help",
            normalizedRect: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05),
            readingOrder: 0
        )
        let standalone = OCRTextRegion(
            text: "https://example.com/help",
            normalizedRect: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.05),
            readingOrder: 1
        )

        XCTAssertFalse(mixed.isProtectedText)
        XCTAssertTrue(standalone.isProtectedText)
        XCTAssertEqual(
            ScreenshotTranslationOverlayWindowController.translatableVisualLines(regions: [mixed, standalone]),
            [mixed.text]
        )

        let blocks = ScreenshotTranslationOverlayWindowController.translationBlocks(
            regions: [mixed, standalone],
            translatedLines: ["欲了解更多信息，请访问 https://example.com/help"]
        )
        XCTAssertEqual(blocks.map(\.text), ["欲了解更多信息，请访问 https://example.com/help"])
        XCTAssertEqual(blocks.first?.normalizedRect, mixed.normalizedRect)
    }

    func testScreenshotLayoutKeepsImpossibleDensityTranslationInPlace() {
        let block = ScreenshotTranslationBlock(
            id: 0,
            normalizedRect: CGRect(x: 0.05, y: 0.45, width: 0.25, height: 0.05),
            text: "A complete translation that cannot fit inside this extremely small region without becoming unreadable.",
            backgroundColor: .white
        )

        let result = ScreenshotTranslationLayoutEngine.layout(
            blocks: [block],
            in: CGSize(width: 120, height: 40)
        )

        XCTAssertEqual(result.blocks[0].fontSize, ScreenshotTranslationLayoutEngine.minimumReadableFontSize)
        XCTAssertFalse(result.blocks[0].usesOverflowCard)
        XCTAssertTrue(result.overflowBlocks.isEmpty)
        XCTAssertEqual(result.blocks[0].text, block.text)
        XCTAssertTrue(CGRect(origin: .zero, size: CGSize(width: 120, height: 40)).contains(result.blocks[0].frame))
    }

    func testScreenshotLayoutFixturesHaveNoOverlapTruncationOrMarkerLeak() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "screenshot-layout-fixtures",
            withExtension: "json"
        ))
        let data = try Data(contentsOf: url)
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(fixtures.count, 8)

        for fixture in fixtures {
            let name = try XCTUnwrap(fixture["name"] as? String)
            let width = try XCTUnwrap(fixture["width"] as? NSNumber).doubleValue
            let height = try XCTUnwrap(fixture["height"] as? NSNumber).doubleValue
            let rawRegions = try XCTUnwrap(fixture["regions"] as? [[Any]])
            let background = name == "dark-background"
                ? OCRBackgroundColor(red: 0.08, green: 0.09, blue: 0.12, variation: 0.14)
                : .white
            let blocks = try rawRegions.enumerated().map { index, values in
                ScreenshotTranslationBlock(
                    id: index,
                    normalizedRect: CGRect(
                        x: try XCTUnwrap(values[0] as? NSNumber).doubleValue,
                        y: try XCTUnwrap(values[1] as? NSNumber).doubleValue,
                        width: try XCTUnwrap(values[2] as? NSNumber).doubleValue,
                        height: try XCTUnwrap(values[3] as? NSNumber).doubleValue
                    ),
                    text: try XCTUnwrap(values[4] as? String),
                    backgroundColor: background
                )
            }
            assertValidLayout(
                ScreenshotTranslationLayoutEngine.layout(
                    blocks: blocks,
                    in: CGSize(width: width, height: height)
                ),
                size: CGSize(width: width, height: height),
                context: name
            )
        }
    }

    func testRandomizedScreenshotLayoutsPreserveGlobalInvariants() {
        var random = DeterministicRandom(seed: 0x5955_414E_4755_49)
        for fixtureIndex in 0..<100 {
            let size = CGSize(
                width: 320 + random.nextUnit() * 1_000,
                height: 180 + random.nextUnit() * 700
            )
            let rowCount = 2 + Int(random.next() % 14)
            let columns = random.next() % 3 == 0 ? 2 : 1
            let blocks = (0..<rowCount).map { index in
                let column = index % columns
                let row = index / columns
                let columnWidth = 0.88 / CGFloat(columns)
                let x = 0.05 + CGFloat(column) * (columnWidth + 0.02)
                let y = max(0.04, 0.92 - CGFloat(row) * (0.055 + random.nextUnit() * 0.055))
                let textLength = 12 + Int(random.next() % 120)
                return ScreenshotTranslationBlock(
                    id: index,
                    normalizedRect: CGRect(
                        x: x,
                        y: y,
                        width: columnWidth,
                        height: 0.025 + random.nextUnit() * 0.045
                    ),
                    text: String(repeating: "readable ", count: max(2, textLength / 9)),
                    backgroundColor: .white
                )
            }
            assertValidLayout(
                ScreenshotTranslationLayoutEngine.layout(blocks: blocks, in: size),
                size: size,
                context: "random-\(fixtureIndex)"
            )
        }
    }

    private func assertValidLayout(
        _ layout: ScreenshotTranslationLayout,
        size: CGSize,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01)
        for block in layout.blocks {
            XCTAssertTrue(bounds.contains(block.frame), "\(context): frame escaped bounds", file: file, line: line)
            XCTAssertGreaterThanOrEqual(
                block.fontSize,
                ScreenshotTranslationLayoutEngine.minimumReadableFontSize,
                context,
                file: file,
                line: line
            )
            XCTAssertFalse(block.text.contains("…"), "\(context): ellipsis leaked", file: file, line: line)
            XCTAssertFalse(block.text.contains("YGUI"), "\(context): internal marker leaked", file: file, line: line)
            XCTAssertFalse(block.usesOverflowCard, "\(context): translation escaped into a separate card", file: file, line: line)
            let consumesAllAvailableHeight = abs(block.frame.height - size.height) <= 0.01
            XCTAssertTrue(
                ScreenshotTranslationLayoutEngine.textFits(block) || consumesAllAvailableHeight,
                "\(context): text neither fits nor uses the full in-place fallback region \(block)",
                file: file,
                line: line
            )
        }
        let visible = layout.blocks
        for first in visible.indices {
            for second in visible.indices where second > first {
                let intersection = visible[first].frame.intersection(visible[second].frame)
                XCTAssertTrue(
                    intersection.isNull || intersection.width <= 0.01 || intersection.height <= 0.01,
                    "\(context): translated frames overlap",
                    file: file,
                    line: line
                )
            }
        }
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

    func testBrowserSelectionScriptsCoverSafariChromeAndEdge() {
        let safari = AccessibilitySelectedTextProvider.browserSelectionScript(for: "com.apple.Safari")
        let chrome = AccessibilitySelectedTextProvider.browserSelectionScript(for: "com.google.Chrome")
        let edge = AccessibilitySelectedTextProvider.browserSelectionScript(for: "com.microsoft.edgemac")

        XCTAssertTrue(safari?.contains("window.getSelection().toString()") == true)
        XCTAssertTrue(safari?.contains("do JavaScript") == true)
        XCTAssertTrue(chrome?.contains("execute active tab") == true)
        XCTAssertTrue(edge?.contains("execute active tab") == true)
        XCTAssertNil(AccessibilitySelectedTextProvider.browserSelectionScript(for: "com.apple.TextEdit"))

        let replacement = AccessibilitySelectedTextProvider.browserReplacementScript(
            for: "com.google.Chrome",
            originalText: "selected \"text\"",
            replacementText: "替换后的\n译文"
        )
        XCTAssertTrue(replacement?.contains("setRangeText") == true)
        XCTAssertTrue(replacement?.contains("contenteditable") == true)
        XCTAssertTrue(replacement?.contains("state.text") == true)
        XCTAssertNil(AccessibilitySelectedTextProvider.browserReplacementScript(
            for: "com.apple.TextEdit",
            originalText: "a",
            replacementText: "b"
        ))
    }

    func testTranslationPipelineCancelsSoleInflightOperation() async {
        let pipeline = TranslationPipeline()
        let segment = TranslationSegment(id: "0", sourceText: "cancel me")
        let request = TranslationRequest(
            segments: [segment],
            targetLanguage: .simplifiedChinese,
            engine: .systemShortcut
        )
        let task = Task {
            try await pipeline.translate(request) {
                try await Task.sleep(for: .seconds(10))
                return [TranslationSegmentResult(id: "0", sourceText: "cancel me", translatedText: "取消")]
            }
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A closed translation request must not keep running")
        } catch is CancellationError {
            // Expected: the sole in-flight engine task is cancelled with its UI request.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
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

    func testOnlineTranslationKeepsStructuredSegmentIdentifiers() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = OnlineTranslationService(session: session)
        TranslationURLProtocol.handler = { request in
            let response = #"{"choices":[{"message":{"content":"{\"segments\":[{\"id\":\"section-a\",\"text\":\"First\"},{\"id\":\"section-b\",\"text\":\"Second\"}]}"}}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }
        defer {
            TranslationURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        let segments = [
            TranslationSegment(id: "section-a", sourceText: "第一段"),
            TranslationSegment(id: "section-b", sourceText: "第二段")
        ]
        let result = try await service.translateSegments(
            segments,
            target: .english,
            configuration: AITranslationConfiguration(
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "test-key"
            )
        )

        XCTAssertEqual(result.map(\.id), ["section-a", "section-b"])
        XCTAssertEqual(result.map(\.translatedText), ["First", "Second"])
    }

    func testTranslationPipelineCachesIdenticalRequestsInMemory() async throws {
        let pipeline = TranslationPipeline(maximumEntryCount: 4, maximumEstimatedBytes: 8_192)
        let request = TranslationRequest(
            segments: [TranslationSegment(id: "0", sourceText: "缓存测试")],
            targetLanguage: .english,
            engine: .systemShortcut
        )
        let counter = TranslationOperationCounter()
        let operation: TranslationPipeline.Operation = {
            await counter.increment()
            return [TranslationSegmentResult(id: "0", sourceText: "缓存测试", translatedText: "Cache test")]
        }

        let first = try await pipeline.translate(request, operation: operation)
        let second = try await pipeline.translate(request, operation: operation)
        let invocationCount = await counter.value
        let cachedEntryCount = await pipeline.cachedEntryCount()

        XCTAssertEqual(first, second)
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(cachedEntryCount, 1)
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

    private func assertRectEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        accuracy: CGFloat = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
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

private struct DeterministicRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUnit() -> CGFloat {
        CGFloat(next() % 10_000) / 10_000
    }
}

private final class StubShortcutTranslationService: SystemShortcutTranslationServicing, @unchecked Sendable {
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

private actor TranslationOperationCounter {
    private(set) var value = 0
    func increment() { value += 1 }
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
