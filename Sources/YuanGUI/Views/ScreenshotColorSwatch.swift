import AppKit
import SwiftUI

struct ScreenshotColorSwatch: NSViewRepresentable {
    let store: ScreenshotEditorStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.openColor))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.borderWidth = 1
        button.toolTip = AppLocalizer.string("颜色")
        button.setAccessibilityLabel(button.toolTip)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.layer?.backgroundColor = store.color.cgColor
        button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.35).cgColor
        button.isEnabled = store.canEditColor
        button.alphaValue = store.canEditColor ? 1 : 0.35
    }
    static func dismantleNSView(_ view: NSButton, coordinator: Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator: NSObject {
        private static weak var owner: Coordinator?
        let store: ScreenshotEditorStore
        private var observing = false
        init(store: ScreenshotEditorStore) { self.store = store }
        @objc func openColor() {
            Self.owner?.store.endStyleEditing()
            Self.owner = self
            let panel = NSColorPanel.shared
            panel.color = store.color
            panel.isContinuous = true
            panel.setTarget(self); panel.setAction(#selector(changeColor))
            store.beginStyleEditing()
            if !observing {
                NotificationCenter.default.addObserver(self, selector: #selector(endInteraction), name: NSWindow.willCloseNotification, object: panel)
                NotificationCenter.default.addObserver(self, selector: #selector(endInteraction), name: NSWindow.didResignKeyNotification, object: panel)
                observing = true
            }
            panel.makeKeyAndOrderFront(nil)
        }
        @objc private func changeColor(_ panel: NSColorPanel) {
            guard store.canEditColor else { return }
            store.beginStyleEditing()
            store.color = panel.color
        }
        @objc private func endInteraction(_ notification: Notification) { store.endStyleEditing() }
        func stop() {
            store.endStyleEditing()
            NotificationCenter.default.removeObserver(self)
            if Self.owner === self { NSColorPanel.shared.setTarget(nil); NSColorPanel.shared.orderOut(nil); Self.owner = nil }
        }
    }
}
