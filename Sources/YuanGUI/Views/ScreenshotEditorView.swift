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
            toolbar
            Divider()
            ScreenshotCanvas(store: store)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(ScreenshotTool.allCases) { tool in
                Button {
                    store.selectedTool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 22, height: 22)
                        .background(store.selectedTool == tool ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(tool.shortcut.uppercased()))")
                .accessibilityLabel(tool.title)
            }

            Divider().frame(height: 22)
            ColorPicker("颜色", selection: Binding(
                get: { Color(nsColor: store.color) },
                set: { store.color = NSColor($0) }
            )).labelsHidden().frame(width: 28)
            Slider(value: $store.lineWidth, in: 2...24, step: 1).frame(width: 100)
            Text("\(Int(store.lineWidth))").monospacedDigit().frame(width: 24)

            Spacer()
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button { store.deleteSelected() } label: { Image(systemName: "delete.backward") }
                .disabled(store.selectedAnnotationID == nil)
                .help(AppLocalizer.string("capture.deleteSelected"))
            Button(role: .destructive) { store.clear() } label: { Image(systemName: "trash") }
                .disabled(store.annotations.isEmpty)
                .help("清除全部标注")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
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

private final class ScreenshotCanvasNSView: NSView {
    var store: ScreenshotEditorStore
    private var effects: ScreenshotRenderEffects
    private var inlineEditor: ScreenshotInlineTextView?
    private var textClickMonitor: Any?
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
        if effects.image !== store.image { effects = ScreenshotRenderEffects(image: store.image); finishText(cancel: true) }
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
    }

    override func mouseDown(with event: NSEvent) {
        finishText(cancel: false)
        window?.makeFirstResponder(self)
        guard let point = imagePoint(for: event) else { return }
        store.beginDrawing(at: point)
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
                if !editor.frame.contains(self.convert(event.locationInWindow, from: nil)) { self.finishText(cancel: false) }
                return event
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard inlineEditor == nil, let point = imagePoint(for: event, clamp: true) else { return }
        store.continueDrawing(to: point, constrained: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard inlineEditor == nil, let point = imagePoint(for: event, clamp: true) else { return }
        store.endDrawing(at: point, constrained: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    private var imageRect: CGRect {
        let insetBounds = bounds.insetBy(dx: 18, dy: 18)
        guard insetBounds.width > 0, insetBounds.height > 0 else { return .zero }
        let scale = min(insetBounds.width / store.imageSize.width, insetBounds.height / store.imageSize.height)
        let size = CGSize(width: store.imageSize.width * scale, height: store.imageSize.height * scale)
        return CGRect(x: insetBounds.midX - size.width / 2, y: insetBounds.midY - size.height / 2, width: size.width, height: size.height)
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
    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" { paste(nil); return }
            super.keyDown(with: event); return
        }
        if event.keyCode == 51 || event.keyCode == 117 { store.deleteSelected(); needsDisplay = true; return }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let tool = ScreenshotTool.allCases.first(where: { $0.shortcut == key }) { store.selectedTool = tool; return }
        if key == "[" || key == "]" { store.lineWidth = min(24, max(2, store.lineWidth + (key == "[" ? -1 : 1))); return }
        super.keyDown(with: event)
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) { store.lineWidth = min(24, max(2, store.lineWidth + (event.scrollingDeltaY > 0 ? 1 : -1))) }
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
