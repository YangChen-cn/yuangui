import AppKit
import SwiftUI

@MainActor
final class MaintenanceWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void

    init(store: MaintenanceStore, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = AppLocalizer.string("window.maintenance")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 720, height: 540)
        window.contentView = NSHostingView(rootView: MaintenanceView(store: store))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window.contentView = nil
        window.delegate = nil
        onClose()
    }
}
