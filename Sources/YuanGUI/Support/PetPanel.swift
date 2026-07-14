import AppKit
import Combine
import SwiftUI

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetPanelController {
    let panel: PetPanel
    private let store: PetStore
    private let chat: ChatStore
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    init(store: PetStore, chat: ChatStore) {
        self.store = store
        self.chat = chat
        let size = PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: store.shouldShowPetBubble,
            showsChat: chat.isPresented
        )
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "元圭与 VCC"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PetRootView(store: store, chat: chat))

        restoreOrPlaceWindow()
        installObservers()
        Publishers.CombineLatest4(store.$showsSystemStatus, store.$smartState, store.$petScale, chat.$isPresented)
            .dropFirst()
            .sink { [weak self] _, _, _, _ in self?.resizeToCurrentLayout() }
            .store(in: &cancellables)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func show() {
        constrainToVisibleScreens()
        panel.orderFrontRegardless()
        store.monitor.setPetVisible(true)
    }

    func hide() {
        panel.orderOut(nil)
        store.monitor.setPetVisible(false)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func focusForChatInput() {
        show()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            UserDefaults.standard.set(panel.frame.origin.x, forKey: "petWindowX")
            UserDefaults.standard.set(panel.frame.origin.y, forKey: "petWindowY")
            UserDefaults.standard.set(true, forKey: "hasSavedPetWindowPosition")
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.constrainToVisibleScreens() }
        })
    }

    private func resizeToCurrentLayout() {
        let targetSize = PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: store.shouldShowPetBubble,
            showsChat: chat.isPresented
        )
        guard panel.frame.size != targetSize else { return }
        var frame = panel.frame
        frame.size = targetSize
        panel.setFrame(frame, display: true, animate: false)
        constrainToVisibleScreens()
    }

    private func restoreOrPlaceWindow() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "hasSavedPetWindowPosition") {
            panel.setFrameOrigin(NSPoint(
                x: defaults.double(forKey: "petWindowX"),
                y: defaults.double(forKey: "petWindowY")
            ))
            constrainToVisibleScreens()
            return
        }
        guard let visible = NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 26,
            y: visible.minY + 28
        ))
    }

    private func constrainToVisibleScreens() {
        guard !NSScreen.screens.isEmpty else { return }
        var frame = panel.frame
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
        panel.setFrameOrigin(frame.origin)
    }
}
