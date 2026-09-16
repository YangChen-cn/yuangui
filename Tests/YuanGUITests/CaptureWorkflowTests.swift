import XCTest
import AppKit
@testable import YuanGUI

final class CaptureWorkflowTests: XCTestCase {
    @MainActor func testSwitchingFromSelectProtectsExistingAnnotationStyle() throws {
        let store = ScreenshotEditorStore(image: try image())
        store.selectTool(.rectangle)
        store.beginDrawing(at: CGPoint(x: 30, y: 30)); store.endDrawing(at: CGPoint(x: 130, y: 130))
        store.selectTool(.select)
        store.beginDrawing(at: CGPoint(x: 60, y: 60)); store.endDrawing(at: CGPoint(x: 60, y: 60))
        XCTAssertNotNil(store.selectedAnnotationID)
        let original = store.annotations
        store.selectTool(.pen)
        XCTAssertNil(store.selectedAnnotationID)
        store.color = .systemGreen; store.lineWidth = 14; store.fontSize = 40
        XCTAssertEqual(store.annotations, original)
    }

    @MainActor func testMarkerNumbersFollowUndoAndRedoContents() throws {
        let store = ScreenshotEditorStore(image: try image())
        func addMarker() {
            store.selectTool(.marker)
            store.beginDrawing(at: CGPoint(x: 40, y: 40)); store.endDrawing(at: CGPoint(x: 40, y: 40))
        }
        func numbers() -> [Int] {
            store.annotations.compactMap { if case let .marker(_, _, n, _) = $0 { return n }; return nil }
        }
        addMarker(); addMarker()
        XCTAssertEqual(numbers(), [1, 2])
        store.clear(); store.undo(); addMarker()
        XCTAssertEqual(numbers(), [1, 2, 3])
        store.undo(); store.redo(); addMarker()
        XCTAssertEqual(numbers(), [1, 2, 3, 4])
        store.clear(); addMarker()
        XCTAssertEqual(numbers(), [1])
    }

    @MainActor func testDrawingPreferencesRestoreWithoutSelectAndValidateInvalidValues() throws {
        let suite = "ScreenshotStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScreenshotEditorStore(image: try image(), defaults: defaults)
        store.selectTool(.arrow)
        store.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.7, alpha: 1)
        store.lineWidth = 12; store.fontSize = 38
        store.selectTool(.select)
        let restored = ScreenshotEditorStore(image: try image(), defaults: defaults)
        XCTAssertEqual(restored.selectedTool, .arrow)
        XCTAssertEqual(restored.lineWidth, 12)
        XCTAssertEqual(restored.fontSize, 38)
        XCTAssertEqual(try XCTUnwrap(restored.color.usingColorSpace(.sRGB)).blueComponent, 0.7, accuracy: 0.001)
        defaults.set(["tool": "select", "lineWidth": -4, "fontSize": 999, "color": [2.0, 0, 0, 1]], forKey: "screenshotEditor.style")
        let invalid = ScreenshotEditorStore(image: try image(), defaults: defaults)
        XCTAssertEqual(invalid.selectedTool, .pen)
        XCTAssertEqual(invalid.lineWidth, 2)
        XCTAssertEqual(invalid.fontSize, 96)
        XCTAssertEqual(invalid.color, .systemRed)
    }
    @MainActor func testCanvasZoomLimitsFitAndActiveGestureProtection() throws {
        let store = ScreenshotEditorStore(image: try image())
        let canvas = ScreenshotCanvasNSView(store: store)
        canvas.frame = CGRect(x: 0, y: 0, width: 516, height: 436)
        XCTAssertEqual(canvas.imageRect.size, CGSize(width: 480, height: 400))
        canvas.setZoom(1)
        XCTAssertEqual(canvas.imageRect.size, store.imageSize)
        canvas.setZoom(100)
        XCTAssertEqual(canvas.imageRect.width, 240 * 8)
        canvas.setZoom(0.01)
        XCTAssertEqual(canvas.imageRect.width, 240 * 0.25)
        canvas.setZoom(nil)
        let fit = canvas.imageRect
        store.beginDrawing(at: CGPoint(x: 30, y: 30))
        canvas.setZoom(1)
        XCTAssertEqual(canvas.imageRect, fit)
        store.cancelGesture()
        canvas.setZoom(1)
        XCTAssertEqual(canvas.imageRect.size, store.imageSize)
    }
    @MainActor func testStyleDragIsOneUndoTransaction() throws {
        let store = ScreenshotEditorStore(image: try image())
        store.selectTool(.rectangle)
        store.beginDrawing(at: CGPoint(x: 30, y: 30)); store.endDrawing(at: CGPoint(x: 130, y: 130))
        store.selectTool(.select)
        store.beginDrawing(at: CGPoint(x: 60, y: 60)); store.endDrawing(at: CGPoint(x: 60, y: 60))
        let original = store.annotations
        store.beginStyleEditing()
        for width in 6...14 { store.lineWidth = CGFloat(width) }
        store.color = .systemBlue
        store.endStyleEditing()
        let edited = store.annotations
        XCTAssertNotEqual(edited, original)
        store.undo()
        XCTAssertEqual(store.annotations, original)
        XCTAssertEqual(store.lineWidth, 5)
        store.redo()
        XCTAssertEqual(store.annotations, edited)
        XCTAssertEqual(store.lineWidth, 14)
    }

    @MainActor func testClearResetsGestureSelectionAndMarkerSequence() throws {
        let store = ScreenshotEditorStore(image: try image())
        store.selectTool(.marker)
        store.beginDrawing(at: CGPoint(x: 40, y: 40)); store.endDrawing(at: CGPoint(x: 40, y: 40))
        store.selectTool(.select)
        store.beginDrawing(at: CGPoint(x: 40, y: 40)); store.continueDrawing(to: CGPoint(x: 80, y: 80))
        store.clear()
        XCTAssertTrue(store.annotations.isEmpty)
        XCTAssertNil(store.selectedAnnotationID)
        XCTAssertNil(store.activeAnnotation)
        XCTAssertFalse(store.hasActiveGesture)
        store.endDrawing(at: CGPoint(x: 80, y: 80))
        XCTAssertTrue(store.annotations.isEmpty)
        store.selectTool(.marker)
        store.beginDrawing(at: CGPoint(x: 40, y: 40)); store.endDrawing(at: CGPoint(x: 40, y: 40))
        guard case let .marker(_, _, number, _) = store.annotations.first else { return XCTFail("Missing marker") }
        XCTAssertEqual(number, 1)
    }

    @MainActor func testTextContextUsesFontSizeAndTextRespondersAreProtected() throws {
        let store = ScreenshotEditorStore(image: try image())
        store.selectTool(.text)
        store.adjustSize(by: 1)
        XCTAssertEqual(store.fontSize, 29)
        XCTAssertEqual(store.lineWidth, 5)
        store.selectTool(.select)
        XCTAssertFalse(store.canEditStyle)
        store.selectTool(.blur)
        XCTAssertFalse(store.canEditStyle)
        store.selectTool(.mosaic)
        XCTAssertFalse(store.canEditColor)
        XCTAssertTrue(ScreenshotEditorWindowController.isTextInput(NSTextView()))
        XCTAssertTrue(ScreenshotEditorWindowController.isTextInput(NSTextField()))
        XCTAssertFalse(ScreenshotEditorWindowController.isTextInput(NSButton()))
    }
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    func testMouseUpRetainsSelectionUntilExplicitCommit() {
        var state = CaptureSelectionState()
        state.begin(at: CGPoint(x: 20, y: 30))
        XCTAssertEqual(state.phase, .dragging)
        state.drag(to: CGPoint(x: 220, y: 130), within: bounds)
        XCTAssertNil(state.commit())
        state.end()
        XCTAssertEqual(state.phase, .selected)
        XCTAssertEqual(state.rect, CGRect(x: 20, y: 30, width: 200, height: 100))
        XCTAssertEqual(state.commit(), state.rect)
        XCTAssertEqual(state.phase, .committed)
        XCTAssertNil(state.commit())
    }
    func testSelectionMoveResizeAndKeyboardStayInsideDisplay() {
        var state = CaptureSelectionState()
        state.select(CGRect(x: 100, y: 100, width: 200, height: 150), within: bounds)
        state.begin(at: CGPoint(x: 170, y: 170))
        state.drag(to: CGPoint(x: 900, y: 700), within: bounds)
        state.end()
        XCTAssertEqual(state.rect.maxX, 800)
        XCTAssertEqual(state.rect.maxY, 600)
        state.nudge(dx: -1, dy: -1, resize: false, within: bounds)
        XCTAssertEqual(state.rect.maxX, 799)
        state.nudge(dx: 1, dy: 1, resize: true, within: bounds)
        XCTAssertEqual(state.rect.size, CGSize(width: 201, height: 151))
    }
    func testEveryHandleAndEdgesCanResize() {
        let initial = CGRect(x: 100, y: 100, width: 200, height: 150)
        for handle in CaptureSelectionState.Handle.allCases {
            var state = CaptureSelectionState()
            state.select(initial, within: bounds)
            let point = handle.point(in: initial)
            state.begin(at: point)
            XCTAssertEqual(state.phase, .adjusting)
            state.drag(to: CGPoint(x: point.x + handle.x * 10, y: point.y + handle.y * 10), within: bounds)
            state.end()
            XCTAssertEqual(state.rect.width, initial.width + abs(handle.x) * 10)
            XCTAssertEqual(state.rect.height, initial.height + abs(handle.y) * 10)
        }
        var state = CaptureSelectionState()
        state.select(initial, within: bounds)
        XCTAssertNotNil(state.hitHandle(CGPoint(x: 100, y: 130)))
    }
    func testSquareCenteredResizeAndReselection() {
        var state = CaptureSelectionState()
        state.begin(at: CGPoint(x: 200, y: 200))
        state.drag(to: CGPoint(x: 100, y: 140), within: bounds, square: true)
        state.end()
        XCTAssertEqual(state.rect.width, 60)
        XCTAssertEqual(state.rect.height, 60)
        let center = CGPoint(x: state.rect.midX, y: state.rect.midY)
        state.begin(at: CGPoint(x: state.rect.maxX, y: state.rect.midY))
        state.drag(to: CGPoint(x: 800, y: center.y), within: bounds, centered: true)
        state.end()
        XCTAssertEqual(state.rect.midX, center.x)
        XCTAssertTrue(bounds.contains(state.rect))
        state.begin(at: CGPoint(x: 700, y: 500))
        XCTAssertEqual(state.phase, .dragging)
        state.end()
        XCTAssertEqual(state.phase, .idle)
    }
    func testSquareConstraintSurvivesShiftReleaseAndResetsForNextSelection() {
        var state = CaptureSelectionState()
        state.begin(at: CGPoint(x: 20, y: 30))
        state.drag(to: CGPoint(x: 220, y: 130), within: bounds, square: true)
        state.drag(to: CGPoint(x: 240, y: 150), within: bounds, square: false)
        state.end()
        XCTAssertEqual(state.rect.size, CGSize(width: 120, height: 120))
        state.begin(at: CGPoint(x: 400, y: 300))
        state.drag(to: CGPoint(x: 600, y: 400), within: bounds)
        state.end()
        XCTAssertEqual(state.rect.size, CGSize(width: 200, height: 100))
    }
    @MainActor func testAnnotationSelectionMoveStyleDeleteUndoAndMarkerNumbers() throws {
        let store = ScreenshotEditorStore(image: try image())
        store.selectTool(.marker)
        store.beginDrawing(at: CGPoint(x: 60, y: 60)); store.endDrawing(at: CGPoint(x: 60, y: 60))
        let id = try XCTUnwrap(store.annotations.first?.id)
        store.selectTool(.select)
        store.beginDrawing(at: CGPoint(x: 60, y: 60))
        store.continueDrawing(to: CGPoint(x: 90, y: 100))
        XCTAssertEqual(store.annotations.first?.bounds.midX, 60)
        store.endDrawing(at: CGPoint(x: 90, y: 100))
        XCTAssertEqual(store.annotations.first?.bounds.midX, 90)
        XCTAssertEqual(store.selectedAnnotationID, id)
        store.color = .systemBlue
        guard case let .marker(_, _, number, style) = store.annotations[0] else { return XCTFail("Expected marker") }
        XCTAssertEqual(number, 1); XCTAssertEqual(style.color, .systemBlue)
        store.deleteSelected(); XCTAssertTrue(store.annotations.isEmpty)
        store.undo(); XCTAssertEqual(store.annotations.count, 1)
        store.selectTool(.marker)
        store.beginDrawing(at: CGPoint(x: 160, y: 160)); store.endDrawing(at: CGPoint(x: 160, y: 160))
        guard case let .marker(_, _, secondNumber, _) = store.annotations[1] else { return XCTFail("Expected marker") }
        XCTAssertEqual(secondNumber, 2)
    }
    @MainActor func testDrawingConstraintsAndImageReplacement() throws {
        let store = ScreenshotEditorStore(image: try image())
        for tool in [ScreenshotTool.rectangle, .ellipse] {
            store.selectTool(tool)
            store.beginDrawing(at: CGPoint(x: 30, y: 30))
            store.endDrawing(at: CGPoint(x: 100, y: 70), constrained: true)
            XCTAssertEqual(store.annotations.last?.bounds.width, store.annotations.last?.bounds.height)
        }
        store.selectTool(.arrow)
        store.beginDrawing(at: CGPoint(x: 30, y: 30))
        store.endDrawing(at: CGPoint(x: 100, y: 35), constrained: true)
        guard case let .line(_, start, end, _, _) = store.annotations.last else { return XCTFail("Expected line") }
        XCTAssertEqual(start.y, end.y, accuracy: 0.001)
        store.replaceImage(try image())
        XCTAssertTrue(store.annotations.isEmpty); XCTAssertFalse(store.canUndo); XCTAssertFalse(store.canRedo)
    }
    func testBlurAndMarkerRenderWithoutChangingDimensions() throws {
        let original = try image()
        let annotations: [ScreenshotAnnotation] = [.blur(id: UUID(), rect: CGRect(x: 30, y: 30, width: 80, height: 70)),
            .marker(id: UUID(), center: CGPoint(x: 100, y: 100), number: 12, style: .init(color: .red, lineWidth: 4, fontSize: 20))]
        let result = try XCTUnwrap(ScreenshotRenderer.render(image: original, annotations: annotations))
        XCTAssertEqual(result.width, original.width); XCTAssertEqual(result.height, original.height)
        XCTAssertFalse(try ScreenshotRenderer.pngData(image: result, annotations: []).isEmpty)
    }
    func testLineHitTestingDoesNotSelectEmptyBoundingBoxCorners() {
        let line = ScreenshotAnnotation.line(id: UUID(), start: CGPoint(x: 10, y: 10), end: CGPoint(x: 190, y: 190),
            style: .init(color: .red, lineWidth: 4, fontSize: 20), arrow: false)
        XCTAssertTrue(line.contains(CGPoint(x: 100, y: 101)))
        XCTAssertFalse(line.contains(CGPoint(x: 10, y: 180)))
    }
    @MainActor func testCaptureSettingsPreserveSavedHotkeysAndDefaultActions() throws {
        let suite = "CaptureSettings-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = QuickToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(fresh.captureDefaultAction, .quickAccess)
        XCTAssertEqual(fresh.screenshotOCRHotKey, .screenshotOCRDefault)
        let custom = HotKeyBinding(keyCode: 12, modifiers: [.control, .option], keyLabel: "Q")
        fresh.saveHotKey(custom, for: .regionScreenshot)
        let returning = QuickToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(returning.captureDefaultAction, .edit)
        XCTAssertEqual(returning.screenshotHotKey, custom)
        returning.setCaptureDefaultAction(.copy)
        XCTAssertEqual(QuickToolsSettingsStore(defaults: defaults).captureDefaultAction, .copy)
    }
    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 240, height: 200))
        return try XCTUnwrap(context.makeImage())
    }
}
