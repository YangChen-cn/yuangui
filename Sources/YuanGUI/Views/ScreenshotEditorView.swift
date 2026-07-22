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
        .sheet(item: $store.textRequest) { request in
            ScreenshotTextSheet { text in
                store.addText(text, at: request.origin)
                store.textRequest = nil
            } cancel: {
                store.textRequest = nil
            }
        }
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
                .help(tool.title)
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
            Button { store.removeLast() } label: { Image(systemName: "delete.backward") }
                .disabled(store.annotations.isEmpty)
                .help("删除最后一项标注")
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
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("取消", action: close)
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

private struct ScreenshotTextSheet: View {
    @State private var text = ""
    let submit: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加文字").font(.headline)
            TextField("输入标注文字", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("添加") { submit(text) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
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
    }
}

private final class ScreenshotCanvasNSView: NSView {
    var store: ScreenshotEditorStore

    init(store: ScreenshotEditorStore) {
        self.store = store
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(store.image, in: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / store.imageSize.width, y: rect.height / store.imageSize.height)
        ScreenshotRenderer.drawAnnotations(store.annotations, image: store.image, in: context)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = imagePoint(for: event) else { return }
        store.beginDrawing(at: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = imagePoint(for: event) else { return }
        store.continueDrawing(to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let point = imagePoint(for: event) else { return }
        store.endDrawing(at: point)
        needsDisplay = true
    }

    private var imageRect: CGRect {
        let insetBounds = bounds.insetBy(dx: 18, dy: 18)
        guard insetBounds.width > 0, insetBounds.height > 0 else { return .zero }
        let scale = min(insetBounds.width / store.imageSize.width, insetBounds.height / store.imageSize.height)
        let size = CGSize(width: store.imageSize.width * scale, height: store.imageSize.height * scale)
        return CGRect(x: insetBounds.midX - size.width / 2, y: insetBounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func imagePoint(for event: NSEvent) -> CGPoint? {
        let local = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        guard rect.contains(local), rect.width > 0, rect.height > 0 else { return nil }
        return CGPoint(
            x: (local.x - rect.minX) * store.imageSize.width / rect.width,
            y: (local.y - rect.minY) * store.imageSize.height / rect.height
        )
    }
}
