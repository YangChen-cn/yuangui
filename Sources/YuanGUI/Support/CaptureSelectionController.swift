import AppKit
import CoreGraphics

@MainActor
final class CaptureSelectionController {
    private var panels: [CaptureSelectionPanel] = []
    private var completion: ((Result<ScreenshotSelection, Error>) -> Void)?
    private var isFinishing = false
    private var lastSelection: ScreenshotSelection?

    var windowNumbers: Set<Int> {
        Set(panels.map(\.windowNumber).filter { $0 > 0 })
    }

    func begin(mode: CaptureMode = .region, windows: [CaptureWindowTarget] = [], completion: @escaping (Result<ScreenshotSelection, Error>) -> Void) {
        cancel()
        self.completion = completion
        isFinishing = false

        panels = NSScreen.screens.compactMap { screen in
            guard let displayID = Self.displayID(for: screen) else { return nil }
            let panel = CaptureSelectionPanel(screen: screen)
            panel.selectionView.mode = mode
            panel.selectionView.targets = windows
            panel.selectionView.screenFrame = screen.frame
            panel.selectionView.onInteract = { [weak self, weak panel] in
                self?.panels.filter { $0 !== panel }.forEach { $0.selectionView.resetSelection() }
            }
            if lastSelection?.displayID == displayID, let lastSelection {
                panel.selectionView.previousRect = lastSelection.globalRect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            }
            panel.selectionView.onComplete = { [weak self] localRect, action, windowID in
                guard let self else { return }
                let globalRect = CGRect(
                    x: screen.frame.minX + localRect.minX,
                    y: screen.frame.minY + localRect.minY,
                    width: localRect.width,
                    height: localRect.height
                )
                let selection = ScreenshotSelection(
                    globalRect: globalRect,
                    displayID: displayID,
                    displayFrame: screen.frame,
                    scale: screen.backingScaleFactor, action: action, windowID: windowID
                )
                if windowID == nil { self.lastSelection = selection }
                self.finish(.success(selection))
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
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { selectionView.onCancel?() }
}

private final class CaptureSelectionView: NSView {
    var onComplete: ((CGRect, CaptureAction, CGWindowID?) -> Void)?
    var onCancel: (() -> Void)?
    var onInteract: (() -> Void)?
    var mode: CaptureMode = .region
    var targets: [CaptureWindowTarget] = []
    var screenFrame = CGRect.zero
    var previousRect: CGRect?
    private var state = CaptureSelectionState()
    private var hoveredWindow: CGWindowID?
    private let hud = NSStackView()
    func resetSelection() {
        guard state.phase != .idle else { return }
        state.reset(); hoveredWindow = nil; refresh()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        hud.orientation = .horizontal
        hud.spacing = 3
        hud.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        hud.wantsLayer = true
        hud.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hud.layer?.cornerRadius = 8
        let actions: [(String, String)] = [("reset", "arrow.counterclockwise"), ("copy", "doc.on.doc"), ("edit", "pencil.tip"),
            ("ocr", "text.viewfinder"), ("translate", "character.bubble"), ("pin", "pin"), ("save", "square.and.arrow.down"), ("confirm", "checkmark")]
        for (key, icon) in actions {
            let button = NSButton(image: NSImage(systemSymbolName: icon, accessibilityDescription: AppLocalizer.string("capture.\(key)"))!, target: self, action: #selector(hudAction(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.toolTip = AppLocalizer.string("capture.\(key)")
            button.bezelStyle = .texturedRounded
            button.setAccessibilityLabel(button.toolTip)
            if key == "confirm" { button.keyEquivalent = "\r"; button.keyEquivalentModifierMask = [] }
            if key == "copy" || key == "save" { button.keyEquivalent = key == "copy" ? "c" : "s"; button.keyEquivalentModifierMask = .command }
            hud.addArrangedSubview(button)
        }
        addSubview(hud)
        hud.isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        guard mode != .region else { return }
        onInteract?()
        let point = convert(event.locationInWindow, from: nil)
        if mode == .screen { state.select(bounds, within: bounds) }
        else {
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            let global = CGPoint(x: screenFrame.minX + point.x, y: primaryTop - screenFrame.minY - point.y)
            if let target = targets.first(where: { $0.frame.contains(global) }) {
                hoveredWindow = target.id
                let local = CGRect(x: target.frame.minX - screenFrame.minX, y: primaryTop - target.frame.maxY - screenFrame.minY,
                                   width: target.frame.width, height: target.frame.height)
                state.select(local, within: bounds)
            } else { state.reset(); hoveredWindow = nil }
        }
        needsDisplay = true
    }
    @objc private func hudAction(_ sender: NSButton) {
        let key = sender.identifier?.rawValue ?? ""
        if key == "reset" { state.reset(); refresh(); return }
        if let action = CaptureAction(rawValue: key) { commit(action) }
    }
    private func commit(_ action: CaptureAction = .confirm) {
        guard let rect = state.commit() else { return }
        if let id = hoveredWindow, let target = targets.first(where: { $0.id == id }) {
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            onComplete?(CGRect(x: target.frame.minX - screenFrame.minX, y: top - target.frame.maxY - screenFrame.minY,
                               width: target.frame.width, height: target.frame.height), action, id)
        } else { onComplete?(rect, action, nil) }
    }
    private func refresh() {
        hud.isHidden = state.phase != .selected || mode != .region
        let size = hud.fittingSize
        let width = size.width, height = size.height
        let gap: CGFloat = 6
        let rect = state.rect
        hud.frame = CGRect(x: min(max(rect.midX - width / 2, 8), bounds.maxX - width - 8),
                           y: max(8, min(rect.minY >= height + gap + 8 ? rect.minY - height - gap : rect.maxY + gap, bounds.maxY - height - 8)), width: width, height: height)
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onInteract?()
        window?.makeKey()
        window?.makeFirstResponder(self)
        if mode != .region { mouseMoved(with: event); commit(); return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        if event.clickCount == 2, state.rect.contains(point) { commit(); return }
        state.begin(at: point)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        state.drag(to: clamped(convert(event.locationInWindow, from: nil)), within: bounds,
                   square: event.modifierFlags.contains(.shift), centered: event.modifierFlags.contains(.option))
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region else { return }
        mouseDragged(with: event)
        state.end()
        refresh()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 { commit(); return }
        let deltas: [UInt16: CGPoint] = [123: CGPoint(x: -1, y: 0), 124: CGPoint(x: 1, y: 0), 125: CGPoint(x: 0, y: -1), 126: CGPoint(x: 0, y: 1)]
        if let delta = deltas[event.keyCode] {
            state.nudge(dx: delta.x, dy: delta.y, resize: event.modifierFlags.contains(.shift), within: bounds)
            refresh(); return
        }
        if event.charactersIgnoringModifiers?.lowercased() == "r", let previousRect {
            state.select(previousRect, within: bounds); refresh(); return
        }
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "c" { commit(.copy); return }
            if event.charactersIgnoringModifiers == "s" { commit(.save); return }
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()

        let rect = state.rect
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
        if mode == .region, state.phase == .selected || state.phase == .adjusting {
            for handle in CaptureSelectionState.Handle.allCases {
                let point = handle.point(in: rect)
                NSColor.white.setFill()
                let dot = NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                dot.fill()
                NSColor.controlAccentColor.setStroke(); dot.stroke()
            }
        }
        drawSizeLabel(for: rect)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func drawHint() {
        let text = AppLocalizer.string("capture.hint.\(mode.rawValue)")
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
