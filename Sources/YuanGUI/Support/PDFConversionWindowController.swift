import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PDFConversionWindowController: NSObject, NSWindowDelegate {
    private let store = PDFConversionStore()
    private let activator = ApplicationWindowActivator()
    private var window: NSWindow?
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    func show() {
        if let window { activator.present(window, makeMain: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = AppLocalizer.string("pdf.title")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 480)
        window.setFrameAutosaveName("YuanGUI.PDFConversion")
        if !window.setFrameUsingName("YuanGUI.PDFConversion") { window.center() }
        window.delegate = self
        window.contentView = NSHostingView(rootView: PDFConversionView(store: store,
            chooseFile: { [weak self] in self?.chooseFile() },
            chooseDestination: { [weak self] in self?.chooseDestination() }))
        self.window = window
        activator.present(window, makeMain: true)
    }

    func stop() { store.close() }

    func windowWillClose(_ notification: Notification) {
        store.close()
        window?.contentView = nil
        window?.delegate = nil
        window = nil
        onClose()
    }

    private func chooseFile() {
        guard let window, !store.isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentInput.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.store.select(panel.urls)
        }
    }

    private func chooseDestination() {
        guard let window, !store.isBusy else { return }
        let panel = NSOpenPanel()
        panel.message = AppLocalizer.string("pdf.destination")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.store.export(to: url)
        }
    }
}
