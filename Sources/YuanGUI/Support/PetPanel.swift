import AppKit
import Combine
import SwiftUI

final class PetPanel: NSPanel {
    var allowedTopOverflow: CGFloat = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return frameRect }
        var frame = frameRect
        frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
        let maximumY = max(visible.minY, visible.maxY - frame.height + allowedTopOverflow)
        frame.origin.y = min(max(frame.origin.y, visible.minY), maximumY)
        return frame
    }
}

private final class PetUnlockHitTargetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct PetUnlockHitTarget: View {
    let unlock: () -> Void

    var body: some View {
        Button(action: unlock) {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("解锁桌宠点击")
    }
}

@MainActor
final class PetPanelController {
    let panel: PetPanel
    private let store: PetStore
    private let chat: ChatStore
    private let maintenance: MaintenanceStore
    private let unlockHitTargetPanel: PetUnlockHitTargetPanel
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    init(store: PetStore, chat: ChatStore, maintenance: MaintenanceStore) {
        self.store = store
        self.chat = chat
        self.maintenance = maintenance
        let size = PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: store.shouldShowPetBubble,
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        unlockHitTargetPanel = PetUnlockHitTargetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 36, height: 36),
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
        panel.contentView = NSHostingView(rootView: PetRootView(store: store, chat: chat, maintenance: maintenance))
        panel.ignoresMouseEvents = store.interactionLocked
        updateAllowedTopOverflow()
        unlockHitTargetPanel.isOpaque = false
        unlockHitTargetPanel.backgroundColor = .clear
        unlockHitTargetPanel.hasShadow = false
        unlockHitTargetPanel.level = .floating
        unlockHitTargetPanel.hidesOnDeactivate = false
        unlockHitTargetPanel.isReleasedWhenClosed = false
        unlockHitTargetPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        unlockHitTargetPanel.contentView = NSHostingView(rootView: PetUnlockHitTarget {
            store.setInteractionLocked(false)
        })

        restoreOrPlaceWindow()
        installObservers()
        Publishers.CombineLatest4(store.$showsSystemStatus, store.$smartState, store.$petScale, chat.$isPresented)
            .dropFirst()
            .sink { [weak self] _, _, _, _ in self?.resizeToCurrentLayout() }
            .store(in: &cancellables)
        store.$interactionLocked
            .removeDuplicates()
            .sink { [weak self] locked in self?.updateInteractionLock(locked) }
            .store(in: &cancellables)
        maintenance.$quickMode
            .removeDuplicates()
            .sink { [weak self] _ in self?.resizeToCurrentLayout() }
            .store(in: &cancellables)
        store.$automaticBubbleSuppressed
            .removeDuplicates()
            .sink { [weak self] _ in self?.resizeToCurrentLayout() }
            .store(in: &cancellables)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func show() {
        constrainToVisibleScreens()
        panel.orderFrontRegardless()
        updateInteractionLock(store.interactionLocked)
        store.monitor.setPetVisible(true)
    }

    func hide() {
        panel.orderOut(nil)
        unlockHitTargetPanel.orderOut(nil)
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
        ) { [weak self] _ in
            guard let self else { return }
            UserDefaults.standard.set(self.panel.frame.origin.x, forKey: "petWindowX")
            UserDefaults.standard.set(self.panel.frame.origin.y, forKey: "petWindowY")
            UserDefaults.standard.set(true, forKey: "hasSavedPetWindowPosition")
            Task { @MainActor in self.positionUnlockHitTarget() }
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
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
        updateAllowedTopOverflow()
        guard panel.frame.size != targetSize else { return }
        var frame = panel.frame
        frame.size = targetSize
        panel.setFrame(frame, display: true, animate: false)
        constrainToVisibleScreens()
        positionUnlockHitTarget()
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
        let maximumY = max(visible.minY, visible.maxY - frame.height + panel.allowedTopOverflow)
        frame.origin.y = min(max(frame.origin.y, visible.minY), maximumY)
        panel.setFrameOrigin(frame.origin)
        positionUnlockHitTarget()
    }

    private func updateInteractionLock(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
        guard locked, panel.isVisible else {
            unlockHitTargetPanel.orderOut(nil)
            return
        }
        positionUnlockHitTarget()
        unlockHitTargetPanel.orderFrontRegardless()
    }

    private func positionUnlockHitTarget() {
        let center = PetLayout.bottomLockCenter(panelWidth: panel.frame.width, showsChat: chat.isPresented)
        unlockHitTargetPanel.setFrameOrigin(NSPoint(
            x: panel.frame.minX + center.x - unlockHitTargetPanel.frame.width / 2,
            y: panel.frame.minY + center.y - unlockHitTargetPanel.frame.height / 2
        ))
    }

    private func updateAllowedTopOverflow() {
        panel.allowedTopOverflow = PetLayout.allowedTopOverflow(
            scale: store.petScale,
            showsBubble: store.shouldShowPetBubble,
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
    }
}
