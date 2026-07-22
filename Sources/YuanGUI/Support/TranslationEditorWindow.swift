import AppKit
import SwiftUI

@MainActor
final class TranslationEditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let store: TranslationEditorStore
    private let onClose: () -> Void
    private var didClose = false

    init(
        snapshot: TranslationTargetSnapshot,
        nonChineseTarget: QuickToolLanguage,
        chineseTarget: QuickToolLanguage,
        engine: TranslationEngine,
        onlineConfiguration: AITranslationConfiguration?,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 352),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        var closeAfterReplacement: (() -> Void)?
        store = TranslationEditorStore(
            snapshot: snapshot,
            nonChineseTarget: nonChineseTarget,
            chineseTarget: chineseTarget,
            engine: engine,
            onlineConfiguration: onlineConfiguration,
            onReplaced: { closeAfterReplacement?() }
        )
        super.init()
        closeAfterReplacement = { [weak self] in self?.window.close() }
        window.title = "元圭与 VCC 翻译小屋"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.minSize = NSSize(width: 400, height: 280)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: TranslationEditorView(
            store: store,
            close: { [weak window] in window?.close() }
        ))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateSourceText(_ text: String) {
        store.updateEditableSourceText(text)
    }

    func setMessage(_ message: String?) {
        store.message = message
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        store.clearSensitiveState()
        onClose()
    }
}
