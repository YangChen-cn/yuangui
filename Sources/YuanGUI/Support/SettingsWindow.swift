import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(petStore: PetStore, aiSettings: AISettingsStore, showPet: @escaping () -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭与 VCC 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 520, height: 430)
        window.contentMaxSize = NSSize(width: 520, height: 430)
        window.contentView = NSHostingView(rootView: SettingsView(
            pet: petStore,
            ai: aiSettings,
            showPet: showPet
        ))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
