import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(petStore: PetStore, aiSettings: AISettingsStore, loginItem: LoginItemStore, focusTimer: FocusTimerStore, music: MusicStore, showPet: @escaping () -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭与 VCC 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 540, height: 500)
        window.contentMaxSize = NSSize(width: 540, height: 500)
        window.contentView = NSHostingView(rootView: SettingsView(
            pet: petStore,
            ai: aiSettings,
            loginItem: loginItem,
            focusTimer: focusTimer,
            music: music,
            showPet: showPet
        ))
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
