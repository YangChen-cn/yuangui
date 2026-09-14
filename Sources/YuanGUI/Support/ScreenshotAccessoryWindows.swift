import AppKit
import SwiftUI
import ImageIO

enum ScreenshotImageLoader {
    static func load(_ url: URL) throws -> CGImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)
              ] as CFDictionary) else { throw ScreenshotOutputError.imageCreationFailed }
        return image
    }
    static func pasteboardImage() -> CGImage? {
        NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

private final class CaptureAccessoryPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class CaptureToastController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    func show(_ text: String) {
        close()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.setAccessibilityLabel(text)
        let panel = NSPanel(contentRect: CGRect(x: screen.visibleFrame.midX - 180, y: screen.visibleFrame.minY + 64, width: 360, height: 48),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        label.frame = CGRect(x: 12, y: 12, width: 336, height: 24)
        panel.contentView?.addSubview(label)
        self.panel = panel
        panel.orderFrontRegardless()
        NSAccessibility.post(element: label, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
    func close() { dismissTask?.cancel(); dismissTask = nil; panel?.close(); panel = nil }
}

@MainActor
final class ScreenshotQuickAccessController: NSObject, NSWindowDelegate {
    private let panel: CaptureAccessoryPanel
    private let onClose: () -> Void
    init(image: CGImage, onClose: @escaping () -> Void, action: @escaping (CaptureAction) -> Void) {
        self.onClose = onClose
        panel = CaptureAccessoryPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 230),
                                      styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.title = AppLocalizer.string("capture.quickAccess")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: VStack(spacing: 12) {
            Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 165)
            HStack(spacing: 16) {
                ForEach([CaptureAction.copy, .save, .edit, .ocr, .translate, .pin], id: \.rawValue) { item in
                    Button { action(item) } label: { Image(systemName: item.symbol) }
                        .help(AppLocalizer.string("capture.\(item.rawValue)"))
                        .accessibilityLabel(AppLocalizer.string("capture.\(item.rawValue)"))
                }
            }
        }.padding(12))
        panel.onEscape = { [weak panel] in panel?.close() }
    }
    func show() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - panel.frame.width - 18, y: screen.visibleFrame.minY + 18))
        }
        panel.orderFrontRegardless()
    }
    func close() { panel.close() }
    func windowWillClose(_ notification: Notification) { panel.contentView = nil; onClose() }
}

extension CaptureAction {
    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .edit: "pencil.tip"
        case .ocr: "text.viewfinder"
        case .translate: "character.bubble"
        case .pin: "pin"
        case .confirm: "checkmark"
        case .quickAccess: "rectangle.bottomthird.inset.filled"
        }
    }
}

@MainActor
final class ScreenshotPinController: NSObject, NSWindowDelegate {
    private let panel: CaptureAccessoryPanel
    private let canvas: PinnedImageView
    private let image: CGImage
    private let directoryPath: () -> String
    private let onClose: () -> Void
    private var outputTask: Task<Void, Never>?
    private var closed = false
    private let toast = CaptureToastController()
    init(image: CGImage, directoryPath: @escaping () -> String, onClose: @escaping () -> Void) {
        self.image = image
        self.directoryPath = directoryPath
        self.onClose = onClose
        canvas = PinnedImageView(image: image)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let limit = screen?.visibleFrame.size ?? CGSize(width: 900, height: 700)
        let scale = min(1, min(limit.width * 0.6 / CGFloat(image.width), limit.height * 0.6 / CGFloat(image.height)))
        panel = CaptureAccessoryPanel(contentRect: CGRect(x: 0, y: 0, width: max(100, CGFloat(image.width) * scale), height: max(64, CGFloat(image.height) * scale)),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = AppLocalizer.string("capture.pin")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = canvas
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        let menu = NSMenu()
        for (key, selector) in [("copy", #selector(copyImage)), ("save", #selector(saveImage)), ("lock", #selector(toggleLock(_:))), ("close", #selector(close))] {
            let item = NSMenuItem(title: AppLocalizer.string("capture.\(key)"), action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        canvas.menu = menu
        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: AppLocalizer.string("capture.close"))!, target: self, action: #selector(close))
        closeButton.bezelStyle = .circular
        closeButton.toolTip = AppLocalizer.string("capture.close")
        closeButton.frame = CGRect(x: 4, y: 4, width: 24, height: 24)
        canvas.addSubview(closeButton)
        if let screen { panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2)) }
    }
    func show() { panel.orderFrontRegardless() }
    @objc func close() { panel.close() }
    func windowWillClose(_ notification: Notification) { closed = true; outputTask?.cancel(); onClose() }
    @objc private func copyImage() { output(save: false) }
    @objc private func saveImage() { output(save: true) }
    @objc private func toggleLock(_ sender: NSMenuItem) { canvas.locked.toggle(); sender.state = canvas.locked ? .on : .off }
    private func output(save: Bool) {
        outputTask?.cancel()
        outputTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = ScreenshotOutputService()
                let data = try await output.pngData(image: image, annotations: [])
                guard !Task.isCancelled, !closed else { return }
                if save { _ = try output.savePNG(data, directoryPath: directoryPath()) }
                else { try output.copyPNG(data) }
            } catch { if !Task.isCancelled, !closed { toast.show(error.localizedDescription) } }
        }
    }
}

private final class PinnedImageView: NSView {
    let image: CGImage
    var locked = false
    private var resizeStart: (point: CGPoint, frame: CGRect)?
    init(image: CGImage) { self.image = image; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        NSColor.white.setStroke()
        let handle = NSBezierPath()
        handle.move(to: CGPoint(x: bounds.maxX - 14, y: 3)); handle.line(to: CGPoint(x: bounds.maxX - 3, y: 14)); handle.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        guard !locked, let window else { return }
        let local = convert(event.locationInWindow, from: nil)
        if local.x > bounds.maxX - 20, local.y < 20 { resizeStart = (NSEvent.mouseLocation, window.frame) }
        else { window.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !locked, let start = resizeStart, let window else { return }
        let ratio = CGFloat(image.height) / CGFloat(image.width)
        let width = max(80, start.frame.width + NSEvent.mouseLocation.x - start.point.x)
        let height = max(60, width * ratio)
        window.setFrame(CGRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
    }
    override func mouseUp(with event: NSEvent) { resizeStart = nil }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close() } else { super.keyDown(with: event) }
    }
}
