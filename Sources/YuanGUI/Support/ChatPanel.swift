import AppKit
import SwiftUI

private final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ChatPanelController {
    private let panel: ChatPanel
    private let petStore: PetStore
    private let chatStore: ChatStore
    private let openSettings: () -> Void

    init(petStore: PetStore, chatStore: ChatStore, openSettings: @escaping () -> Void) {
        self.petStore = petStore
        self.chatStore = chatStore
        self.openSettings = openSettings
        panel = ChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "和元圭、VCC 聊聊"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: ChatView(
            chat: chatStore,
            pet: petStore,
            openSettings: openSettings,
            close: { [weak panel] in panel?.orderOut(nil) }
        ))
    }

    func show(relativeTo petPanel: NSPanel?) {
        let screen = petPanel?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let petFrame = petPanel?.frame ?? NSRect(x: visible.midX, y: visible.midY, width: 1, height: 1)
        var x = petFrame.minX - size.width + min(90, petFrame.width * 0.25)
        if x < visible.minX + 10 { x = petFrame.maxX - min(90, petFrame.width * 0.25) }
        x = min(max(x, visible.minX + 10), visible.maxX - size.width - 10)
        var y = petFrame.midY - size.height / 2
        y = min(max(y, visible.minY + 10), visible.maxY - size.height - 10)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
