import AppKit
import SwiftUI

struct ScreenshotEditorView: View {
    @ObservedObject var store: ScreenshotEditorStore
    let copy: () async -> Void
    let save: () async -> Void
    let copyAndSave: () async -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenshotEditorToolbar(store: store)
            Divider()
            ScreenshotCanvas(store: store)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if store.isExporting { ProgressView().controlSize(.small) }
            if let message = store.message {
                Text(AppLocalizer.string(message)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("取消", action: close)
            Button(AppLocalizer.string("capture.openImage")) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg, .tiff]
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    do { store.replaceImage(try ScreenshotImageLoader.load(url)) }
                    catch { store.message = error.localizedDescription }
                }
            }.disabled(store.isExporting)
            Button("复制") { Task { await copy() } }
                .disabled(store.isExporting)
            Button("保存") { Task { await save() } }
                .disabled(store.isExporting)
            Button("复制并保存") { Task { await copyAndSave() } }
                .buttonStyle(.borderedProminent)
                .disabled(store.isExporting)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }
}

private struct ScreenshotCanvas: NSViewRepresentable {
    @ObservedObject var store: ScreenshotEditorStore

    func makeNSView(context: Context) -> ScreenshotCanvasNSView {
        ScreenshotCanvasNSView(store: store)
    }

    func updateNSView(_ nsView: ScreenshotCanvasNSView, context: Context) {
        nsView.store = store
        nsView.needsDisplay = true
        nsView.synchronizeImage()
    }
}

final class ScreenshotCanvasNSView: NSView {
    var store: ScreenshotEditorStore
    private var effects: ScreenshotRenderEffects
    private var inlineEditor: ScreenshotInlineTextView?
    private var textClickMonitor: Any?
    private var zoom: CGFloat?
    private var pan = CGPoint.zero
    private var panStart: CGPoint?
    var spaceHeld = false { didSet { refreshCursor() } }
    deinit { if let textClickMonitor { NSEvent.removeMonitor(textClickMonitor) } }

    init(store: ScreenshotEditorStore) {
        self.store = store
        effects = ScreenshotRenderEffects(image: store.image)
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.makeFirstResponder(self) }
        else { finishText(cancel: true) }
    }
    func synchronizeImage() {
        if effects.image !== store.image { effects = ScreenshotRenderEffects(image: store.image); finishText(cancel: true); setZoom(nil) }
        refreshCursor()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(store.image, in: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / store.imageSize.width, y: rect.height / store.imageSize.height)
        ScreenshotRenderer.drawAnnotations(
            store.displayedAnnotations,
            activeAnnotation: store.activeAnnotation,
            image: store.image,
            effects: effects,
            in: context
        )
        if let selected = store.selectedBounds {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2 * store.imageSize.width / rect.width)
            context.setLineDash(phase: 0, lengths: [5, 3])
            context.stroke(selected.insetBy(dx: -4, dy: -4))
        }
        context.restoreGState()
        let label = "\(Int((zoom ?? fitScale) * 100))%"
        label.draw(at: CGPoint(x: 12, y: 10), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.windowBackgroundColor])
    }

    override func mouseDown(with event: NSEvent) {
        if inlineEditor != nil { finishText(cancel: false); return }
        window?.makeFirstResponder(self)
        if spaceHeld { panStart = convert(event.locationInWindow, from: nil); NSCursor.closedHand.set(); return }
        guard let point = imagePoint(for: event) else { return }
        store.beginDrawing(at: point)
        if store.selectedTool == .select, store.selectedAnnotationID != nil { NSCursor.closedHand.set() }
        if let request = store.textRequest {
            let editor = ScreenshotInlineTextView()
            let rect = imageRect
            let x = rect.minX + request.origin.x * rect.width / store.imageSize.width
            let y = rect.minY + request.origin.y * rect.height / store.imageSize.height
            let width = min(300, max(80, bounds.width - 36))
            editor.frame = CGRect(x: max(18, min(x, bounds.maxX - width - 18)), y: max(18, min(y, bounds.maxY - 88)), width: width, height: 70)
            editor.isRichText = false
            editor.font = .systemFont(ofSize: max(13, store.fontSize * rect.width / store.imageSize.width))
            editor.textColor = store.color
            editor.backgroundColor = .textBackgroundColor
            editor.setAccessibilityLabel(AppLocalizer.string("capture.inlineText"))
            editor.finish = { [weak self] cancel in self?.finishText(cancel: cancel) }
            addSubview(editor)
            inlineEditor = editor
            window?.makeFirstResponder(editor)
            textClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window === self.window, let editor = self.inlineEditor else { return event }
                if !editor.frame.contains(self.convert(event.locationInWindow, from: nil)) { self.finishText(cancel: false); return nil }
                return event
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = panStart {
            let point = convert(event.locationInWindow, from: nil)
            pan.x += point.x - start.x; pan.y += point.y - start.y
            panStart = point; constrainPan(); needsDisplay = true; return
        }
        guard inlineEditor == nil, let point = imagePoint(for: event, clamp: true) else { return }
        store.continueDrawing(to: point, constrained: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if panStart != nil { panStart = nil; refreshCursor(); return }
        guard inlineEditor == nil, let point = imagePoint(for: event, clamp: true) else { return }
        store.endDrawing(at: point, constrained: event.modifierFlags.contains(.shift))
        refreshCursor()
        needsDisplay = true
    }

    var imageRect: CGRect {
        let insetBounds = bounds.insetBy(dx: 18, dy: 18)
        guard insetBounds.width > 0, insetBounds.height > 0 else { return .zero }
        let scale = zoom ?? fitScale
        let size = CGSize(width: store.imageSize.width * scale, height: store.imageSize.height * scale)
        return CGRect(x: insetBounds.midX - size.width / 2 + pan.x, y: insetBounds.midY - size.height / 2 + pan.y, width: size.width, height: size.height)
    }
    private var fitScale: CGFloat { max(0.01, min((bounds.width - 36) / store.imageSize.width, (bounds.height - 36) / store.imageSize.height)) }
    func setZoom(_ value: CGFloat?) {
        guard inlineEditor == nil, !store.hasActiveGesture else { return }
        zoom = value.map { min(8, max(0.25, $0)) }; pan = .zero
        needsDisplay = true
    }
    private func constrainPan() {
        let scale = zoom ?? fitScale
        let x = max(0, (store.imageSize.width * scale - bounds.width + 36) / 2)
        let y = max(0, (store.imageSize.height * scale - bounds.height + 36) / 2)
        pan.x = min(x, max(-x, pan.x)); pan.y = min(y, max(-y, pan.y))
    }
    private func zoomBy(_ multiplier: CGFloat) {
        guard inlineEditor == nil, !store.hasActiveGesture else { return }
        zoom = min(8, max(0.25, (zoom ?? fitScale) * multiplier))
        constrainPan(); needsDisplay = true
    }
    override func magnify(with event: NSEvent) { zoomBy(1 + event.magnification) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .inVisibleRect], owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { refreshCursor() }
    override func mouseMoved(with event: NSEvent) {
        if store.selectedTool == .select, let point = imagePoint(for: event), store.annotations.contains(where: { $0.contains(point) }) { NSCursor.openHand.set() }
        else { refreshCursor() }
    }
    func refreshCursor() {
        guard inlineEditor == nil else { return }
        if spaceHeld { NSCursor.openHand.set() }
        else if store.selectedTool == .text { NSCursor.iBeam.set() }
        else if store.selectedTool == .select { NSCursor.arrow.set() }
        else { NSCursor.crosshair.set() }
    }

    private func imagePoint(for event: NSEvent, clamp: Bool = false) -> CGPoint? {
        var local = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        if clamp { local = CGPoint(x: min(max(local.x, rect.minX), rect.maxX - 0.001), y: min(max(local.y, rect.minY), rect.maxY - 0.001)) }
        guard rect.contains(local), rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(
            x: (local.x - rect.minX) * store.imageSize.width / rect.width,
            y: (local.y - rect.minY) * store.imageSize.height / rect.height
        )
    }
    private func finishText(cancel: Bool) {
        guard let editor = inlineEditor else { return }
        if !cancel, let request = store.textRequest { store.addText(editor.string, at: request.origin) }
        inlineEditor = nil
        if let textClickMonitor { NSEvent.removeMonitor(textClickMonitor); self.textClickMonitor = nil }
        editor.removeFromSuperview()
        store.textRequest = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { zoomBy(exp(event.scrollingDeltaY * 0.01)) }
        else if event.modifierFlags.contains(.option) {
            if event.phase == .began { store.beginStyleEditing() }
            if event.scrollingDeltaY != 0 { store.adjustSize(by: event.scrollingDeltaY > 0 ? 1 : -1) }
            if event.phase == .ended || event.phase == .cancelled { store.endStyleEditing() }
        }
        else { super.scrollWheel(with: event) }
    }
    @objc func paste(_ sender: Any?) {
        if let image = ScreenshotImageLoader.pasteboardImage() { store.replaceImage(image) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { store.isExporting ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !store.isExporting else { return false }
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], urls.count == 1,
           ["png", "jpg", "jpeg", "tif", "tiff"].contains(urls[0].pathExtension.lowercased()) {
            do { store.replaceImage(try ScreenshotImageLoader.load(urls[0])); return true }
            catch { store.message = error.localizedDescription }
        } else if let image = NSImage(pasteboard: sender.draggingPasteboard)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            store.replaceImage(image); return true
        }
        return false
    }
}

private final class ScreenshotInlineTextView: NSTextView {
    var finish: ((Bool) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish?(true); return }
        if event.keyCode == 36, event.modifierFlags.contains(.command) { finish?(false); return }
        super.keyDown(with: event)
    }
}
