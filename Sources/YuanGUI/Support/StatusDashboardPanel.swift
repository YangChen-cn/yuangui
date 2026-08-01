import AppKit
import SwiftUI

private final class StatusDashboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class StatusDashboardHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? (bounds.contains(point) ? self : nil)
    }

    override func scrollWheel(with event: NSEvent) {
        // A child NSScrollView receives scrolling first. If it forwards an
        // unhandled boundary event, terminate the responder chain here so the
        // wheel gesture cannot reach a window beneath this borderless panel.
    }
}

@MainActor
final class StatusDashboardPanelController {
    // Keep the AppKit boundary limited to behavior SwiftUI's MenuBarExtra does
    // not expose: section-dependent sizing, status-item anchoring, cross-Space
    // placement, and the existing outside-click monitoring contract.
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
    private let updater: AppUpdateStore
    private let dashboardState = DashboardPanelState()
    private let hostModel = DashboardHostModel()
    private let panel: StatusDashboardPanel
    private var hostingView: StatusDashboardHostingView<StatusDashboardRootView>!
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var anchorRect = NSRect.zero
    private var visibleFrame = NSRect.zero

    init(
        store: PetStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        externalAudioInterruption: ExternalAudioInterruptionController,
        quickTools: QuickToolsController,
        updater: AppUpdateStore,
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
        self.updater = updater
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
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.isExcludedFromWindowsMenu = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        installContent()
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func hide() {
        hostModel.isPresented = false
        if panel.isKeyWindow {
            panel.resignKey()
        }
        panel.orderOut(nil)
        removeClickMonitors()
        store.monitor.setDashboardVisible(false)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        store.refreshDesktopIconVisibility()
        let visible = screen.visibleFrame
        visibleFrame = visible
        let size = DashboardPanelLayout.size(
            in: visible,
            section: dashboardState.selectedSection,
            musicSource: music.playback.source
        )
        let width = size.width
        let height = size.height
        hostModel.width = width
        hostModel.maximumHeight = max(visible.height - DashboardPanelLayout.screenInset * 2, 0)
        hostModel.isPresented = true
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

        store.monitor.setDashboardVisible(true)
        store.monitor.refresh()
        store.weather.start()
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickMonitors()
    }

    private func installContent() {
        guard hostingView == nil else { return }
        let rootView = StatusDashboardRootView(
            store: store,
            focusTimer: focusTimer,
            music: music,
            externalAudioInterruption: externalAudioInterruption,
            quickTools: quickTools,
            panelState: dashboardState,
            hostModel: hostModel,
            updater: updater,
            togglePet: togglePet,
            showPet: showPet,
            openSettings: openSettings,
            dismiss: { [weak self] in self?.hide() },
            layoutDidChange: { [weak self] section, source in
                self?.resize(for: section, musicSource: source)
            },
            appActions: appActions
        )
        hostingView = StatusDashboardHostingView<StatusDashboardRootView>(rootView: rootView)
        panel.contentView = hostingView
    }

    private func resize(for section: DashboardSection, musicSource: MusicSource) {
        guard panel.isVisible, !visibleFrame.isEmpty else { return }
        let size = DashboardPanelLayout.size(
            in: visibleFrame,
            section: section,
            musicSource: musicSource
        )
        hostModel.width = size.width
        hostModel.maximumHeight = max(visibleFrame.height - DashboardPanelLayout.screenInset * 2, 0)
        let inset = DashboardPanelLayout.screenInset
        let top = min(anchorRect.minY - 6, visibleFrame.maxY - inset)
        let y = max(visibleFrame.minY + inset, top - size.height)
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: y, width: size.width, height: size.height),
            display: true
        )
    }

    private func installClickMonitors() {
        removeClickMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  event.window !== self.panel,
                  !self.isAuxiliaryPopupWindow(event.window) else {
                return event
            }
            Task { @MainActor in self.closeIfPointerIsOutside() }
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

    private func isAuxiliaryPopupWindow(_ window: NSWindow?) -> Bool {
        guard let window, window !== panel else { return true }
        if window.level == .popUpMenu || window is NSPanel { return true }
        if window.parent === panel || panel.childWindows?.contains(where: { $0 === window }) == true {
            return true
        }
        return false
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
