import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenshotEditorStore: ObservableObject {
    struct TextRequest: Identifiable, Equatable {
        let id = UUID()
        let origin: CGPoint
    }

    let image: CGImage
    let imageSize: CGSize

    @Published var selectedTool: ScreenshotTool = .pen
    @Published var color: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 5
    @Published var fontSize: CGFloat = 28
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published var textRequest: TextRequest?
    @Published var message: String?
    @Published var isExporting = false

    private var undoStack: [[ScreenshotAnnotation]] = []
    private var redoStack: [[ScreenshotAnnotation]] = []
    private var gestureStartSnapshot: [ScreenshotAnnotation]?
    private var activeAnnotationValue: ScreenshotAnnotation?
    private var activeDrawingStart: CGPoint?

    var activeAnnotation: ScreenshotAnnotation? { activeAnnotationValue }

    init(image: CGImage) {
        self.image = image
        imageSize = CGSize(width: image.width, height: image.height)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var style: AnnotationStyle {
        AnnotationStyle(color: color, lineWidth: lineWidth, fontSize: fontSize)
    }

    func beginDrawing(at point: CGPoint) {
        guard imageBounds.contains(point) else { return }
        if selectedTool == .text {
            textRequest = TextRequest(origin: point)
            return
        }

        gestureStartSnapshot = annotations
        activeDrawingStart = point
        let id = UUID()
        switch selectedTool {
        case .pen:
            activeAnnotationValue = .stroke(id: id, points: [point], style: style, highlighter: false)
        case .highlighter:
            var highlighterStyle = style
            highlighterStyle.color = color.withAlphaComponent(0.34)
            highlighterStyle.lineWidth = max(10, lineWidth * 2.4)
            activeAnnotationValue = .stroke(id: id, points: [point], style: highlighterStyle, highlighter: true)
        case .line:
            activeAnnotationValue = .line(id: id, start: point, end: point, style: style, arrow: false)
        case .arrow:
            activeAnnotationValue = .line(id: id, start: point, end: point, style: style, arrow: true)
        case .rectangle:
            activeAnnotationValue = .rectangle(id: id, rect: CGRect(origin: point, size: .zero), style: style, ellipse: false)
        case .ellipse:
            activeAnnotationValue = .rectangle(id: id, rect: CGRect(origin: point, size: .zero), style: style, ellipse: true)
        case .mosaic:
            activeAnnotationValue = .mosaic(id: id, points: [point], width: max(18, lineWidth * 3))
        case .text:
            break
        }
    }

    func continueDrawing(to point: CGPoint) {
        guard let activeAnnotation = activeAnnotationValue else { return }
        let point = clamped(point)
        switch activeAnnotation {
        case let .stroke(id, points, style, highlighter):
            guard let previous = points.last, Self.isMeaningfullyDifferent(point, from: previous) else { return }
            activeAnnotationValue = .stroke(id: id, points: points + [point], style: style, highlighter: highlighter)
        case let .line(id, start, _, style, arrow):
            activeAnnotationValue = .line(id: id, start: start, end: point, style: style, arrow: arrow)
        case let .rectangle(id, rect, style, ellipse):
            activeAnnotationValue = .rectangle(
                id: id,
                rect: Self.normalizedRect(from: activeDrawingStart ?? rect.origin, to: point),
                style: style,
                ellipse: ellipse
            )
        case let .mosaic(id, points, width):
            guard let previous = points.last, Self.isMeaningfullyDifferent(point, from: previous) else { return }
            activeAnnotationValue = .mosaic(id: id, points: points + [point], width: width)
        case .text:
            break
        }
    }

    func endDrawing(at point: CGPoint) {
        continueDrawing(to: point)
        guard let completed = activeAnnotationValue else { return }
        activeAnnotationValue = nil
        activeDrawingStart = nil
        annotations.append(completed)
        if let gestureStartSnapshot {
            undoStack.append(gestureStartSnapshot)
            redoStack.removeAll()
        }
        gestureStartSnapshot = nil
    }

    func addText(_ text: String, at origin: CGPoint) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pushUndoSnapshot()
        annotations.append(.text(id: UUID(), origin: origin, text: text, style: style))
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func removeLast() {
        guard !annotations.isEmpty else { return }
        pushUndoSnapshot()
        annotations.removeLast()
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        pushUndoSnapshot()
        annotations.removeAll()
    }

    private var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), imageSize.width),
            y: min(max(point.y, 0), imageSize.height)
        )
    }

    private func pushUndoSnapshot() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    private static func isMeaningfullyDifferent(_ point: CGPoint, from previous: CGPoint) -> Bool {
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        return dx * dx + dy * dy >= 1.5 * 1.5
    }

    private static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
