import AppKit
import SwiftUI

/// 日记窗口
private final class DiaryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 日记窗口控制器
@MainActor
final class DiaryWindowController {
    private let store: DiaryFeature
    private var window: NSWindow?

    init(store: DiaryFeature) {
        self.store = store
    }

    func show() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = DiaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭恋爱手账"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 450)
        window.center()
        window.contentView = NSHostingView(
            rootView: DiaryMainView(store: store)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 处理 accessory app 激活时序
        DispatchQueue.main.async {
            window.makeKey()
            window.makeMain()
        }

        self.window = window
    }
}
