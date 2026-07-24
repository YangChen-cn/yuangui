import AppKit
import SwiftUI

private final class DiaryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DiaryWindowController: NSObject, NSWindowDelegate {
    private let store: DiaryFeature
    private var window: NSWindow?
    private var allowClose = false
    private var closeTask: Task<Void, Never>?

    init(store: DiaryFeature) {
        self.store = store
        super.init()
    }

    func show() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = DiaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭恋爱手账"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("YuanGUI.DiaryWindow")
        if !window.setFrameUsingName("YuanGUI.DiaryWindow") { window.center() }
        window.delegate = self
        window.contentView = NSHostingView(rootView: DiaryMainView(store: store))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            window.makeKey()
            window.makeMain()
        }
        self.window = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        guard closeTask == nil else { return false }
        closeTask = Task { [weak self, weak sender] in
            guard let self, let sender else { return }
            let saved = await store.flush()
            if saved {
                finishClosing(sender)
            } else {
                await handleSaveFailure(window: sender)
            }
            closeTask = nil
        }
        return false
    }

    private func handleSaveFailure(window: NSWindow) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "日记尚未保存"
        alert.informativeText = "保存失败。可以重试，或仍然关闭窗口并保留当前进程中的编辑内容。"
        alert.addButton(withTitle: "重试保存")
        alert.addButton(withTitle: "仍然关闭")
        if alert.runModal() == .alertFirstButtonReturn {
            let saved = await store.flush()
            if saved { finishClosing(window) }
        } else {
            finishClosing(window)
        }
    }

    private func finishClosing(_ window: NSWindow) {
        allowClose = true
        window.performClose(nil)
        allowClose = false
    }
}
