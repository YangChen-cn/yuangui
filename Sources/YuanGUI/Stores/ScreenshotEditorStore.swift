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

    @Published private(set) var selectedTool: ScreenshotTool = .pen
    @Published var color: NSColor = .systemRed { didSet { updateSelectedStyle(); saveStyle() } }
    @Published var lineWidth: CGFloat = 5 { didSet { updateSelectedStyle(); saveStyle() } }
    @Published var fontSize: CGFloat = 28 { didSet { updateSelectedStyle(); saveStyle() } }
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
    private var styleSnapshot: [ScreenshotAnnotation]?
    private var loadingStyle = false
    private let defaults: UserDefaults?
    private var lastDrawingTool: ScreenshotTool = .pen
    private static let preferencesKey = "screenshotEditor.style"

    func selectTool(_ tool: ScreenshotTool) {
        endStyleEditing()
        cancelGesture()
        selectedTool = tool
        if tool != .select {
            selectedAnnotationID = nil
            lastDrawingTool = tool
        }
        saveStyle()
    }
    private func saveStyle() {
        guard !loadingStyle, let defaults, let rgb = color.usingColorSpace(.sRGB) else { return }
        defaults.set([
            "tool": lastDrawingTool.rawValue,
            "color": [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent],
            "lineWidth": lineWidth, "fontSize": fontSize
        ], forKey: Self.preferencesKey)
    }
    private func updateNextMarker() {
        nextMarker = (annotations.compactMap { annotation -> Int? in
            if case let .marker(_, _, number, _) = annotation { return number }
            return nil
        }.max() ?? 0) + 1
    }

    var selectedAnnotation: ScreenshotAnnotation? { annotations.first { $0.id == selectedAnnotationID } }
    var styleTool: ScreenshotTool? { selectedTool == .select ? selectedAnnotation?.tool : selectedTool }
    var usesFontSize: Bool { styleTool == .text || styleTool == .marker }
    var canEditStyle: Bool { styleTool != nil && styleTool != .blur }
    var canEditColor: Bool { canEditStyle && styleTool != .mosaic }
    var hasActiveGesture: Bool { activeDrawingStart != nil || activeAnnotationValue != nil }

    func beginStyleEditing() { if styleSnapshot == nil { styleSnapshot = annotations } }
    func endStyleEditing() {
        if let snapshot = styleSnapshot, snapshot != annotations {
            objectWillChange.send()
            undoStack.append(snapshot); redoStack.removeAll()
        }
        styleSnapshot = nil
    }
    func adjustSize(by delta: CGFloat) {
        guard canEditStyle else { return }
        if usesFontSize { fontSize = min(96, max(10, fontSize + delta)) }
        else { lineWidth = min(24, max(2, lineWidth + delta)) }
    }
    func cancelGesture() {
        activeAnnotationValue = nil; activeDrawingStart = nil
        movingAnnotation = nil; gestureStartSnapshot = nil
    }
    private func loadSelectedStyle() {
        guard let value = selectedAnnotation?.editingStyle else { return }
        loadingStyle = true
        color = value.color; lineWidth = value.lineWidth; fontSize = value.fontSize
        loadingStyle = false
    }

    var activeAnnotation: ScreenshotAnnotation? { activeAnnotationValue }

    init(image: CGImage, defaults: UserDefaults? = nil) {
        self.image = image
        self.defaults = defaults
        if let saved = defaults?.dictionary(forKey: Self.preferencesKey) {
            if let raw = saved["tool"] as? String, let tool = ScreenshotTool(rawValue: raw), tool != .select {
                selectedTool = tool; lastDrawingTool = tool
            }
            if let components = saved["color"] as? [Double], components.count == 4,
               components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                color = NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
            }
            if let value = saved["lineWidth"] as? Double, value.isFinite { lineWidth = min(24, max(2, value)) }
            if let value = saved["fontSize"] as? Double, value.isFinite { fontSize = min(96, max(10, value)) }
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var style: AnnotationStyle {
        AnnotationStyle(color: color, lineWidth: lineWidth, fontSize: fontSize)
    }

    func beginDrawing(at point: CGPoint) {
        endStyleEditing()
        guard imageBounds.contains(point) else { return }
        if selectedTool == .select {
            let hit = annotations.last(where: { $0.contains(point) })
            selectedAnnotationID = hit?.id
            loadSelectedStyle()
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
        guard let completed = activeAnnotationValue else { cancelGesture(); return }
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
        endStyleEditing(); cancelGesture()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        updateNextMarker()
        if selectedAnnotation == nil { selectedAnnotationID = nil }
        loadSelectedStyle()
    }

    func redo() {
        endStyleEditing(); cancelGesture()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        updateNextMarker()
        if selectedAnnotation == nil { selectedAnnotationID = nil }
        loadSelectedStyle()
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
        endStyleEditing(); cancelGesture()
        guard let id = selectedAnnotationID, annotations.contains(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }
    private func updateSelectedStyle() {
        guard !loadingStyle, selectedTool == .select else { return }
        guard let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        let updated = annotations[index].transformed(style: style)
        guard updated != annotations[index] else { return }
        if styleSnapshot == nil { pushUndoSnapshot() }
        annotations[index] = updated
    }
    func replaceImage(_ image: CGImage) {
        guard !isExporting else { return }
        self.image = image
        annotations = []
        undoStack = []; redoStack = []
        activeAnnotationValue = nil; movingAnnotation = nil; gestureStartSnapshot = nil; activeDrawingStart = nil
        selectedAnnotationID = nil; textRequest = nil; nextMarker = 1
        styleSnapshot = nil
    }

    func clear() {
        endStyleEditing()
        if !annotations.isEmpty { pushUndoSnapshot() }
        annotations.removeAll()
        selectedAnnotationID = nil; textRequest = nil; nextMarker = 1
        cancelGesture()
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
