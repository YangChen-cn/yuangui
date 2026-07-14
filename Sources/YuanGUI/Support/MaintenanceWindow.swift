import AppKit
import SwiftUI

@MainActor
final class MaintenanceWindowController {
    private let window: NSWindow

    init(store: MaintenanceStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭与 VCC 清理屋"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 540)
        window.contentView = NSHostingView(rootView: MaintenanceView(store: store))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
