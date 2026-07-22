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
    private var activeAnnotationID: UUID?

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
        let id = UUID()
        activeAnnotationID = id
        switch selectedTool {
        case .pen:
            annotations.append(.stroke(id: id, points: [point], style: style, highlighter: false))
        case .highlighter:
            var highlighterStyle = style
            highlighterStyle.color = color.withAlphaComponent(0.34)
            highlighterStyle.lineWidth = max(10, lineWidth * 2.4)
            annotations.append(.stroke(id: id, points: [point], style: highlighterStyle, highlighter: true))
        case .line:
            annotations.append(.line(id: id, start: point, end: point, style: style, arrow: false))
        case .arrow:
            annotations.append(.line(id: id, start: point, end: point, style: style, arrow: true))
        case .rectangle:
            annotations.append(.rectangle(id: id, rect: CGRect(origin: point, size: .zero), style: style, ellipse: false))
        case .ellipse:
            annotations.append(.rectangle(id: id, rect: CGRect(origin: point, size: .zero), style: style, ellipse: true))
        case .mosaic:
            annotations.append(.mosaic(id: id, points: [point], width: max(18, lineWidth * 3)))
        case .text:
            break
        }
    }

    func continueDrawing(to point: CGPoint) {
        guard let id = activeAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let point = clamped(point)
        switch annotations[index] {
        case let .stroke(id, points, style, highlighter):
            annotations[index] = .stroke(id: id, points: points + [point], style: style, highlighter: highlighter)
        case let .line(id, start, _, style, arrow):
            annotations[index] = .line(id: id, start: start, end: point, style: style, arrow: arrow)
        case let .rectangle(id, rect, style, ellipse):
            annotations[index] = .rectangle(id: id, rect: Self.normalizedRect(from: rect.origin, to: point), style: style, ellipse: ellipse)
        case let .mosaic(id, points, width):
            annotations[index] = .mosaic(id: id, points: points + [point], width: width)
        case .text:
            break
        }
    }

    func endDrawing(at point: CGPoint) {
        continueDrawing(to: point)
        guard activeAnnotationID != nil else { return }
        activeAnnotationID = nil
        if let gestureStartSnapshot {
            undoStack.append(gestureStartSnapshot)
            redoStack.removeAll()
        }
        gestureStartSnapshot = nil
        objectWillChange.send()
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
        objectWillChange.send()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        objectWillChange.send()
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
        objectWillChange.send()
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
