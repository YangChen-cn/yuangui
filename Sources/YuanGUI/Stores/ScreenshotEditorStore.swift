import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenshotEditorStore: ObservableObject {
    struct TextRequest: Identifiable, Equatable {
        let id = UUID()
        let origin: CGPoint
    }

    @Published private(set) var image: CGImage
    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    @Published var selectedTool: ScreenshotTool = .pen
    @Published var color: NSColor = .systemRed { didSet { updateSelectedStyle() } }
    @Published var lineWidth: CGFloat = 5 { didSet { updateSelectedStyle() } }
    @Published var fontSize: CGFloat = 28 { didSet { updateSelectedStyle() } }
    @Published private(set) var selectedAnnotationID: UUID?
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published var textRequest: TextRequest?
    @Published var message: String?
    @Published var isExporting = false

    private var undoStack: [[ScreenshotAnnotation]] = []
    private var redoStack: [[ScreenshotAnnotation]] = []
    private var gestureStartSnapshot: [ScreenshotAnnotation]?
    private var activeAnnotationValue: ScreenshotAnnotation?
    private var activeDrawingStart: CGPoint?
    private var movingAnnotation: ScreenshotAnnotation?
    private var nextMarker = 1

    var activeAnnotation: ScreenshotAnnotation? { activeAnnotationValue }

    init(image: CGImage) {
        self.image = image
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var style: AnnotationStyle {
        AnnotationStyle(color: color, lineWidth: lineWidth, fontSize: fontSize)
    }

    func beginDrawing(at point: CGPoint) {
        guard imageBounds.contains(point) else { return }
        if selectedTool == .select {
            let hit = annotations.last(where: { $0.contains(point) })
            selectedAnnotationID = hit?.id
            movingAnnotation = hit
            activeDrawingStart = point
            gestureStartSnapshot = annotations
            return
        }
        if selectedAnnotationID != nil { selectedAnnotationID = nil }
        if selectedTool == .text {
            textRequest = TextRequest(origin: point)
            return
        }

        gestureStartSnapshot = annotations
        activeDrawingStart = point
        let id = UUID()
        switch selectedTool {
        case .select: break
        case .marker:
            activeAnnotationValue = .marker(id: id, center: point, number: nextMarker, style: style)
            nextMarker += 1
        case .blur:
            activeAnnotationValue = .blur(id: id, rect: CGRect(origin: point, size: .zero))
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

    func continueDrawing(to point: CGPoint, constrained: Bool = false) {
        if let movingAnnotation, let start = activeDrawingStart {
            let rect = movingAnnotation.bounds
            let dx = min(max(point.x - start.x, -rect.minX), imageSize.width - rect.maxX)
            let dy = min(max(point.y - start.y, -rect.minY), imageSize.height - rect.maxY)
            activeAnnotationValue = movingAnnotation.transformed(dx: dx, dy: dy)
            return
        }
        guard let activeAnnotation = activeAnnotationValue else { return }
        var point = clamped(point)
        if constrained, let start = activeDrawingStart {
            let dx = point.x - start.x, dy = point.y - start.y
            if selectedTool == .line || selectedTool == .arrow {
                let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                let distance = hypot(dx, dy)
                point = clamped(CGPoint(x: start.x + cos(angle) * distance, y: start.y + sin(angle) * distance))
            } else if selectedTool == .rectangle || selectedTool == .ellipse {
                let side = min(abs(dx), abs(dy))
                point = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
            }
        }
        switch activeAnnotation {
        case let .blur(id, rect): activeAnnotationValue = .blur(id: id, rect: Self.normalizedRect(from: activeDrawingStart ?? rect.origin, to: point))
        case .marker: break
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

    func endDrawing(at point: CGPoint, constrained: Bool = false) {
        continueDrawing(to: point, constrained: constrained)
        guard let completed = activeAnnotationValue else { return }
        activeAnnotationValue = nil
        activeDrawingStart = nil
        if movingAnnotation != nil, let index = annotations.firstIndex(where: { $0.id == completed.id }) {
            annotations[index] = completed
        } else { annotations.append(completed) }
        movingAnnotation = nil
        if let gestureStartSnapshot, gestureStartSnapshot != annotations {
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
    var displayedAnnotations: [ScreenshotAnnotation] {
        movingAnnotation == nil || activeAnnotationValue == nil ? annotations : annotations.filter { $0.id != movingAnnotation?.id }
    }
    var selectedBounds: CGRect? {
        if let activeAnnotationValue, movingAnnotation != nil { return activeAnnotationValue.bounds }
        return annotations.first(where: { $0.id == selectedAnnotationID })?.bounds
    }
    func deleteSelected() {
        guard let id = selectedAnnotationID, annotations.contains(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }
    private func updateSelectedStyle() {
        guard let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        let updated = annotations[index].transformed(style: style)
        guard updated != annotations[index] else { return }
        pushUndoSnapshot()
        annotations[index] = updated
    }
    func replaceImage(_ image: CGImage) {
        guard !isExporting else { return }
        self.image = image
        annotations = []
        undoStack = []; redoStack = []
        activeAnnotationValue = nil; movingAnnotation = nil; gestureStartSnapshot = nil; activeDrawingStart = nil
        selectedAnnotationID = nil; textRequest = nil; nextMarker = 1
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
