import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let store: ScreenshotEditorStore
    private let outputService = ScreenshotOutputService()
    private let directoryPath: () -> String
    private let onClose: () -> Void
    private var closed = false
    private var keyMonitor: Any?
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

    init(image: CGImage, directoryPath: @escaping () -> String, onClose: @escaping () -> Void) {
        store = ScreenshotEditorStore(image: image)
        self.directoryPath = directoryPath
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = AppLocalizer.string("编辑截图")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ScreenshotEditorView(
            store: store,
            copy: { [weak self] in await self?.export(copy: true, save: false) },
            save: { [weak self] in await self?.export(copy: false, save: true) },
            copyAndSave: { [weak self] in await self?.export(copy: true, save: true) },
            close: { [weak self] in self?.window.close() }
        ))
        window.center()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === self.window, self.window.isKeyWindow,
                  !Self.isTextInput(self.window.firstResponder) else { return event }
            return self.dispatch(event) ? nil : event
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func close() { window.close() }
    func windowDidResignKey(_ notification: Notification) {
        canvas?.spaceHeld = false
        store.endStyleEditing()
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        store.endStyleEditing(); store.cancelGesture()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        onClose()
    }

    static func isTextInput(_ responder: NSResponder?) -> Bool {
        responder is NSTextView || responder is NSTextField
    }
    private var canvas: ScreenshotCanvasNSView? {
        func find(_ view: NSView?) -> ScreenshotCanvasNSView? {
            if let canvas = view as? ScreenshotCanvasNSView { return canvas }
            for child in view?.subviews ?? [] { if let found = find(child) { return found } }
            return nil
        }
        return find(window.contentView)
    }
    private func dispatch(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyUp {
            if key == " " { canvas?.spaceHeld = false; return true }
            return false
        }
        if flags.contains(.command), !flags.contains(.control), !flags.contains(.option) {
            switch key {
            case "c": Task { await export(copy: true, save: flags.contains(.shift)) }; return true
            case "s": Task { await export(copy: false, save: true) }; return true
            case "v": canvas?.paste(nil); return true
            case "z": if flags.contains(.shift) { store.redo() } else { store.undo() }; return true
            default: return false
            }
        }
        guard flags.isEmpty else { return false }
        if event.keyCode == 53 {
            if store.hasActiveGesture { store.cancelGesture(); canvas?.needsDisplay = true }
            else { window.close() }
            return true
        }
        if event.keyCode == 51 || event.keyCode == 117 { store.deleteSelected(); return true }
        if let tool = ScreenshotTool.allCases.first(where: { $0.shortcut == key }) {
            store.endStyleEditing(); store.cancelGesture(); store.selectedTool = tool
            canvas?.refreshCursor(); return true
        }
        if key == "[" || key == "]" { store.adjustSize(by: key == "[" ? -1 : 1); return true }
        if key == " " { canvas?.spaceHeld = true; return true }
        if key == "0" || key == "1" { canvas?.setZoom(key == "0" ? nil : 1); return true }
        return false
    }

    private func export(copy: Bool, save: Bool) async {
        guard !store.isExporting else { return }
        store.endStyleEditing()
        store.isExporting = true
        store.message = nil
        do {
            let data = try await outputService.pngData(image: store.image, annotations: store.annotations)
            guard !closed, !Task.isCancelled else { store.isExporting = false; return }
            var savedURL: URL?
            if copy { try outputService.copyPNG(data) }
            if save { savedURL = try outputService.savePNG(data, directoryPath: directoryPath()) }
            if let savedURL {
                store.message = "已保存到 \(savedURL.deletingLastPathComponent().path)"
            } else {
                store.message = "已复制到剪贴板"
            }
            window.close()
        } catch {
            store.message = error.localizedDescription
        }
        store.isExporting = false
    }
}
