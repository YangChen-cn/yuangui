import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let store: ScreenshotEditorStore
    private let outputService = ScreenshotOutputService()
    private let directoryPath: () -> String
    private let onClose: () -> Void

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
        window.title = "编辑截图"
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
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func export(copy: Bool, save: Bool) async {
        guard !store.isExporting else { return }
        store.isExporting = true
        store.message = nil
        do {
            let data = try await outputService.pngData(image: store.image, annotations: store.annotations)
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
