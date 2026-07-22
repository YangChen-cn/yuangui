import AppKit
import CoreGraphics

@MainActor
final class CaptureSelectionController {
    private var panels: [CaptureSelectionPanel] = []
    private var completion: ((Result<ScreenshotSelection, Error>) -> Void)?
    private var isFinishing = false

    var windowNumbers: Set<Int> {
        Set(panels.map(\.windowNumber).filter { $0 > 0 })
    }

    func begin(completion: @escaping (Result<ScreenshotSelection, Error>) -> Void) {
        cancel()
        self.completion = completion
        isFinishing = false

        panels = NSScreen.screens.compactMap { screen in
            guard let displayID = Self.displayID(for: screen) else { return nil }
            let panel = CaptureSelectionPanel(screen: screen)
            panel.selectionView.onComplete = { [weak self] localRect in
                guard let self else { return }
                let globalRect = CGRect(
                    x: screen.frame.minX + localRect.minX,
                    y: screen.frame.minY + localRect.minY,
                    width: localRect.width,
                    height: localRect.height
                )
                self.finish(.success(ScreenshotSelection(
                    globalRect: globalRect,
                    displayID: displayID,
                    displayFrame: screen.frame,
                    scale: screen.backingScaleFactor
                )))
            }
            panel.selectionView.onCancel = { [weak self] in
                self?.finish(.failure(CancellationError()))
            }
            return panel
        }

        for panel in panels { panel.orderFrontRegardless() }
        let mouseLocation = NSEvent.mouseLocation
        let activePanel = panels.first(where: { $0.frame.contains(mouseLocation) }) ?? panels.first
        activePanel?.makeKey()
        activePanel?.makeFirstResponder(activePanel?.selectionView)
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
    }

    func cancel() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        completion = nil
        isFinishing = false
    }

    private func finish(_ result: Result<ScreenshotSelection, Error>) {
        guard !isFinishing else { return }
        isFinishing = true
        hide()
        let handler = completion
        completion = nil
        handler?(result)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private final class CaptureSelectionPanel: NSPanel {
    let selectionView = CaptureSelectionView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CaptureSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clamped(convert(event.locationInWindow, from: nil))
        let rect = selectionRect
        if rect.width >= 3, rect.height >= 3 {
            onComplete?(rect)
        } else {
            NSSound.beep()
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        let rect = selectionRect
        guard rect.width > 0, rect.height > 0 else {
            drawHint()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 2
        outline.stroke()
        drawSizeLabel(for: rect)
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).intersection(bounds)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func drawHint() {
        let text = "拖动选择截图区域 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let scale = window?.screen?.backingScaleFactor ?? 1
        let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let size = text.size(withAttributes: attributes)
        let x = min(max(rect.minX, bounds.minX + 4), bounds.maxX - size.width - 8)
        let y = rect.minY > size.height + 10 ? rect.minY - size.height - 8 : rect.maxY + 6
        text.draw(at: CGPoint(x: x + 4, y: min(y, bounds.maxY - size.height - 4)), withAttributes: attributes)
    }
}
