import AppKit
import SwiftUI

private final class DiaryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DiaryWindowController: NSObject, NSWindowDelegate {
    private let store: DiaryFeature
    private let onClose: () -> Void
    private let windowActivator: ApplicationWindowActivating
    private var window: NSWindow?
    private var quickEntryWindow: NSWindow?
    private var allowClose = false
    private var closeTask: Task<Void, Never>?
    private var didNotifyIdle = false

    init(
        store: DiaryFeature,
        windowActivator: ApplicationWindowActivating? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.store = store
        self.windowActivator = windowActivator ?? ApplicationWindowActivator()
        self.onClose = onClose
        super.init()
    }

    func show() {
        if let window {
            windowActivator.present(window, makeMain: true)
            return
        }

        let window = DiaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppLocalizer.string("手帐本")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 450)
        window.setFrameAutosaveName("YuanGUI.DiaryWindow")
        if !window.setFrameUsingName("YuanGUI.DiaryWindow") { window.center() }
        window.delegate = self
        window.contentView = NSHostingView(rootView: DiaryMainView(store: store))
        didNotifyIdle = false
        windowActivator.present(window, makeMain: true)
        self.window = window
    }

    func showQuickEntry() {
        if let quickEntryWindow {
            windowActivator.present(quickEntryWindow, makeMain: true)
            return
        }

        let window = DiaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppLocalizer.string("快速记录")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 470)
        window.maxSize = NSSize(width: 620, height: 760)
        window.setFrameAutosaveName("YuanGUI.QuickDiaryWindow")
        if !window.setFrameUsingName("YuanGUI.QuickDiaryWindow") { window.center() }
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: QuickDiaryEntryView(
                store: store,
                onSaved: { [weak self] in self?.closeQuickEntry() },
                onCancel: { [weak self] in self?.closeQuickEntry() },
                onOpenFullDiary: { [weak self] in
                    guard let self else { return }
                    self.closeQuickEntry(notifyWhenIdle: false)
                    self.show()
                }
            )
        )
        didNotifyIdle = false
        quickEntryWindow = window
        windowActivator.present(window, makeMain: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === quickEntryWindow { return true }
        if allowClose { return true }
        guard closeTask == nil else { return false }
        closeTask = Task { [weak self, weak sender] in
            guard let self, let sender else { return }
            let saved = await store.completeCurrentEditingSession()
            if saved {
                finishClosing(sender)
            } else {
                await handleSaveFailure(window: sender)
            }
            closeTask = nil
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        if closedWindow === quickEntryWindow {
            closedWindow.contentView = nil
            closedWindow.delegate = nil
            quickEntryWindow = nil
        } else if closedWindow === window {
            closedWindow.contentView = nil
            closedWindow.delegate = nil
            window = nil
        } else {
            return
        }
        notifyIfIdle()
    }

    private func handleSaveFailure(window: NSWindow) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalizer.string("日记尚未保存")
        alert.informativeText = AppLocalizer.string("保存失败。可以重试，或仍然关闭窗口并保留当前进程中的编辑内容。")
        alert.addButton(withTitle: AppLocalizer.string("重试保存"))
        alert.addButton(withTitle: AppLocalizer.string("仍然关闭"))
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

    private func closeQuickEntry(notifyWhenIdle: Bool = true) {
        guard let quickEntryWindow else { return }
        quickEntryWindow.delegate = nil
        quickEntryWindow.contentView = nil
        quickEntryWindow.close()
        self.quickEntryWindow = nil
        if notifyWhenIdle { notifyIfIdle() }
    }

    private func notifyIfIdle() {
        guard window == nil, quickEntryWindow == nil, !didNotifyIdle else { return }
        didNotifyIdle = true
        onClose()
    }
}
