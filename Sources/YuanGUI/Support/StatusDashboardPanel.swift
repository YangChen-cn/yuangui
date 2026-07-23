import AppKit
import SwiftUI

private final class StatusDashboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusDashboardPanelController {
    private static let preferredWidth = MenuBarDashboardView.preferredWidth
    private static let preferredHeight: CGFloat = 480
    private static let screenInset: CGFloat = 8

    private let store: PetStore
    private let focusTimer: FocusTimerStore
    private let music: MusicFeature
    private let quickTools: QuickToolsController
    private let togglePet: () -> Void
    private let showPet: () -> Void
    private let openSettings: () -> Void
    private let appActions: AppActions
    private let panel: StatusDashboardPanel
    private var hostingView: NSHostingView<AnyView>!
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var anchorRect = NSRect.zero

    init(
        store: PetStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        quickTools: QuickToolsController,
        togglePet: @escaping () -> Void,
        showPet: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        appActions: AppActions = .disabled
    ) {
        self.store = store
        self.focusTimer = focusTimer
        self.music = music
        self.quickTools = quickTools
        self.togglePet = togglePet
        self.showPet = showPet
        self.openSettings = openSettings
        self.appActions = appActions
        panel = StatusDashboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: Self.preferredHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "元圭与 VCC 状态"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        installContent(width: Self.preferredWidth, height: Self.preferredHeight)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func hide() {
        panel.orderOut(nil)
        removeClickMonitors()
        store.monitor.setDashboardVisible(false)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = min(Self.preferredWidth, visible.width - Self.screenInset * 2)
        let height = min(Self.preferredHeight, visible.height - Self.screenInset * 2)
        installContent(width: width, height: height)
        panel.setContentSize(NSSize(width: width, height: height))

        if let window = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            anchorRect = window.convertToScreen(rectInWindow)
        } else {
            anchorRect = NSRect(x: visible.midX, y: visible.maxY, width: 1, height: 1)
        }

        let proposedX = anchorRect.midX - width / 2
        let x = min(max(proposedX, visible.minX + Self.screenInset), visible.maxX - width - Self.screenInset)
        let top = min(anchorRect.minY - 6, visible.maxY - Self.screenInset)
        let y = max(visible.minY + Self.screenInset, top - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        store.monitor.refresh()
        store.monitor.setDashboardVisible(true)
        store.weather.start()
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickMonitors()
    }

    private func installContent(width: CGFloat, height: CGFloat) {
        let rootView = AnyView(
            MenuBarDashboardView(
                store: store,
                focusTimer: focusTimer,
                music: music,
                quickTools: quickTools,
                dashboardWidth: width,
                dashboardHeight: height,
                togglePet: togglePet,
                showPet: showPet,
                openSettings: openSettings,
                dismiss: { [weak self] in self?.hide() }
            )
            .environment(\.appActions, appActions)
        )
        if hostingView == nil {
            hostingView = NSHostingView(rootView: rootView)
            panel.contentView = hostingView
        } else {
            hostingView.rootView = rootView
        }
    }

    private func installClickMonitors() {
        removeClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
            return event
        }
    }

    private func closeIfPointerIsOutside() {
        let point = NSEvent.mouseLocation
        guard !panel.frame.contains(point), !anchorRect.insetBy(dx: -4, dy: -4).contains(point) else { return }
        hide()
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}
