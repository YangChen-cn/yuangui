import AppKit
import SwiftUI

private final class StatusDashboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusDashboardPanelController {
    private static let preferredWidth = DashboardDesign.preferredWidth
    private static let preferredHeight = DashboardDesign.preferredHeight

    private let store: PetStore
    private let focusTimer: FocusTimerStore
    private let music: MusicFeature
    private let externalAudioInterruption: ExternalAudioInterruptionController
    private let quickTools: QuickToolsController
    private let togglePet: () -> Void
    private let showPet: () -> Void
    private let openSettings: () -> Void
    private let appActions: AppActions
    private let panel: StatusDashboardPanel
    private var hostingView: NSHostingView<AnyView>!
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var anchorRect = NSRect.zero

    init(
        store: PetStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        externalAudioInterruption: ExternalAudioInterruptionController,
        quickTools: QuickToolsController,
        togglePet: @escaping () -> Void,
        showPet: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        appActions: AppActions = .disabled
    ) {
        self.store = store
        self.focusTimer = focusTimer
        self.music = music
        self.externalAudioInterruption = externalAudioInterruption
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
        let size = DashboardPanelLayout.size(in: visible)
        let width = size.width
        let height = size.height
        installContent(width: width, height: height)
        panel.setContentSize(NSSize(width: width, height: height))

        if let window = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            anchorRect = window.convertToScreen(rectInWindow)
        } else {
            anchorRect = NSRect(x: visible.midX, y: visible.maxY, width: 1, height: 1)
        }

        let proposedX = anchorRect.midX - width / 2
        let inset = DashboardPanelLayout.screenInset
        let x = min(max(proposedX, visible.minX + inset), visible.maxX - width - inset)
        let top = min(anchorRect.minY - 6, visible.maxY - inset)
        let y = max(visible.minY + inset, top - height)
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
                externalAudioInterruption: externalAudioInterruption,
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
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.charactersIgnoringModifiers == "," else { return event }
            Task { @MainActor in
                self?.hide()
                self?.openSettings()
            }
            return nil
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
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
        localKeyMonitor = nil
    }
}
