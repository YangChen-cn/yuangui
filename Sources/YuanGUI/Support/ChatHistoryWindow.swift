import AppKit
import SwiftUI

@MainActor
final class ChatHistoryWindowController {
    private let window: NSWindow

    init(chat: ChatStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭与 VCC 对话历史"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 660, height: 420)
        window.contentView = NSHostingView(rootView: ChatHistoryView(chat: chat))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
