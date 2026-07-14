import AppKit
import Combine
import QuartzCore
import SwiftUI

final class PetPanel: NSPanel {
    var allowedTopOverflow: CGFloat = 0
    var isUserDragging = false
    var bypassScreenConstraint = false
    var dragEndedAction: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if isUserDragging || bypassScreenConstraint { return frameRect }
        guard let visible = screen?.visibleFrame else { return frameRect }
        var frame = frameRect
        frame.origin = PetLayout.constrainedOrigin(
            frame.origin,
            panelSize: frame.size,
            visibleFrame: visible,
            allowedTopOverflow: allowedTopOverflow
        )
        return frame
    }
}

private final class PetEdgePeekPanel: NSPanel {
    var restoreAction: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PetLockedToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetPanelController {
    let panel: PetPanel
    private let store: PetStore
    private let chat: ChatStore
    private let maintenance: MaintenanceStore
    private let lockedToolbarPanel: PetLockedToolbarPanel
    private let edgePeekPanel: PetEdgePeekPanel
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var dockedEdge: PetDockEdge?
    private var lastExpandedOrigin = CGPoint.zero
    private var isDockTransitioning = false
    private var lockedHoverTimer: Timer?
    private var lastLockedPointerInside = false

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
        lockedToolbarPanel = PetLockedToolbarPanel(
            contentRect: NSRect(origin: .zero, size: PetLayout.bottomToolbarPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let peekPanel = PetEdgePeekPanel(
            contentRect: NSRect(origin: .zero, size: PetLayout.edgePeekSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        edgePeekPanel = peekPanel
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
        lockedToolbarPanel.isOpaque = false
        lockedToolbarPanel.backgroundColor = .clear
        lockedToolbarPanel.hasShadow = false
        lockedToolbarPanel.level = .floating
        lockedToolbarPanel.hidesOnDeactivate = false
        lockedToolbarPanel.isReleasedWhenClosed = false
        lockedToolbarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        lockedToolbarPanel.contentView = NSHostingView(rootView: PetBottomControlsView(store: store, chat: chat))
        edgePeekPanel.isOpaque = false
        edgePeekPanel.backgroundColor = .clear
        edgePeekPanel.hasShadow = false
        edgePeekPanel.level = .floating
        edgePeekPanel.hidesOnDeactivate = false
        edgePeekPanel.isReleasedWhenClosed = false
        edgePeekPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        edgePeekPanel.contentView = NSHostingView(rootView: PetEdgePeekView(store: store, edge: .left) { [weak peekPanel] in
            peekPanel?.restoreAction?()
        })

        restoreOrPlaceWindow()
        lastExpandedOrigin = panel.frame.origin
        dockedEdge = UserDefaults.standard.string(forKey: "petDockedEdge").flatMap(PetDockEdge.init(rawValue:))
        panel.dragEndedAction = { [weak self] in self?.finishUserDrag() }
        edgePeekPanel.restoreAction = { [weak self] in self?.restoreFromEdge(animated: true) }
        installObservers()
        Publishers.CombineLatest4(store.$showsSystemStatus, store.$smartState, store.$petScale, chat.$isPresented)
            .dropFirst()
            .sink { [weak self] _, _, _, _ in self?.resizeToCurrentLayout() }
            .store(in: &cancellables)
        store.$interactionLocked
            .removeDuplicates()
            .sink { [weak self] locked in self?.updateInteractionLock(locked) }
            .store(in: &cancellables)
        store.$lockedControlsVisible
            .removeDuplicates()
            .sink { [weak self] visible in self?.updateLockedToolbarVisibility(visible: visible) }
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
        lockedHoverTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func show() {
        if dockedEdge != nil {
            panel.orderOut(nil)
            lockedToolbarPanel.orderOut(nil)
            refreshEdgePeekContent()
            resizeEdgePeekPanel()
            positionEdgePeek()
            edgePeekPanel.orderFrontRegardless()
            store.monitor.setPetVisible(true)
            return
        }
        constrainToVisibleScreens()
        panel.orderFrontRegardless()
        updateInteractionLock(store.interactionLocked)
        store.monitor.setPetVisible(true)
    }

    func hide() {
        panel.orderOut(nil)
        lockedToolbarPanel.orderOut(nil)
        edgePeekPanel.orderOut(nil)
        stopLockedHoverTracking()
        store.monitor.setPetVisible(false)
    }

    func toggle() {
        (panel.isVisible || edgePeekPanel.isVisible) ? hide() : show()
    }

    func focusForChatInput() {
        if dockedEdge != nil {
            restoreFromEdge(animated: false)
        }
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.panel.isUserDragging,
                      !self.isDockTransitioning,
                      self.dockedEdge == nil else { return }
                self.lastExpandedOrigin = self.panel.frame.origin
                self.persistExpandedOrigin()
                self.positionLockedToolbar()
            }
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
        if dockedEdge != nil {
            resizeEdgePeekPanel()
            positionEdgePeek()
            return
        }
        constrainToVisibleScreens()
        positionLockedToolbar()
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
        if dockedEdge != nil {
            positionEdgePeek()
            return
        }
        var frame = panel.frame
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        frame.origin = PetLayout.constrainedOrigin(
            frame.origin,
            panelSize: frame.size,
            visibleFrame: visible,
            allowedTopOverflow: panel.allowedTopOverflow
        )
        panel.setFrameOrigin(frame.origin)
        lastExpandedOrigin = frame.origin
        persistExpandedOrigin()
        positionLockedToolbar()
    }

    private func updateInteractionLock(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
        guard locked, panel.isVisible, dockedEdge == nil else {
            stopLockedHoverTracking()
            lockedToolbarPanel.orderOut(nil)
            return
        }
        startLockedHoverTracking()
        updateLockedToolbarVisibility(visible: store.lockedControlsVisible)
    }

    private func updateLockedToolbarVisibility(visible: Bool) {
        guard store.interactionLocked,
              visible,
              panel.isVisible,
              dockedEdge == nil else {
            lockedToolbarPanel.orderOut(nil)
            return
        }
        positionLockedToolbar()
        lockedToolbarPanel.orderFrontRegardless()
    }

    private func positionLockedToolbar() {
        let bottom = chat.isPresented
            ? PetLayout.bottomToolbarChatBottomPadding
            : PetLayout.bottomToolbarNormalBottomPadding
        lockedToolbarPanel.setFrameOrigin(NSPoint(
            x: panel.frame.midX - lockedToolbarPanel.frame.width / 2,
            y: panel.frame.minY + bottom
        ))
    }

    private func startLockedHoverTracking() {
        guard lockedHoverTimer == nil else { return }
        lastLockedPointerInside = false
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollLockedPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        lockedHoverTimer = timer
    }

    private func stopLockedHoverTracking() {
        lockedHoverTimer?.invalidate()
        lockedHoverTimer = nil
    }

    private func pollLockedPointer() {
        guard store.interactionLocked, panel.isVisible, dockedEdge == nil else {
            stopLockedHoverTracking()
            return
        }
        let location = NSEvent.mouseLocation
        let inside = isPointerInsideLockedRegion(at: location)

        if inside {
            // The pet panel ignores mouse events while locked, so poll the global
            // pointer and keep the original toolbar alive for the whole hover.
            store.revealLockedControls()
        } else if !inside, lastLockedPointerInside {
            store.scheduleLockedControlsHide(after: 3)
        }
        lastLockedPointerInside = inside
    }

    private func isPointerInsideLockedRegion(at location: CGPoint) -> Bool {
        let petArea = panel.frame.insetBy(dx: -8, dy: -8)
        let toolbarArea = lockedToolbarPanel.frame.insetBy(dx: -8, dy: -8)
        return petArea.contains(location) || toolbarArea.contains(location)
    }

    private func updateAllowedTopOverflow() {
        panel.allowedTopOverflow = PetLayout.allowedTopOverflow(
            scale: store.petScale,
            showsBubble: store.shouldShowPetBubble,
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
    }

    private func finishUserDrag() {
        guard !isDockTransitioning else { return }
        let screen = screenAtMouse() ?? screenForExpandedPet()
        guard let screen else { return }
        let petVisualFrame = PetLayout.petVisualFrame(
            panelFrame: panel.frame,
            scale: store.petScale,
            showsChat: chat.isPresented
        )
        if let edge = PetLayout.dockingEdge(for: petVisualFrame, in: screen.visibleFrame) {
            dock(to: edge, on: screen)
        } else {
            lastExpandedOrigin = panel.frame.origin
            persistExpandedOrigin()
            positionLockedToolbar()
        }
    }

    private func dock(to edge: PetDockEdge, on screen: NSScreen) {
        guard dockedEdge == nil else { return }
        let targetExpandedOrigin = PetLayout.expandedOrigin(
            edge: edge,
            previousOrigin: panel.frame.origin,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            allowedTopOverflow: panel.allowedTopOverflow
        )
        lastExpandedOrigin = targetExpandedOrigin
        dockedEdge = edge
        UserDefaults.standard.set(edge.rawValue, forKey: "petDockedEdge")
        persistExpandedOrigin()
        lockedToolbarPanel.orderOut(nil)
        refreshEdgePeekContent()
        resizeEdgePeekPanel()
        positionEdgePeek(on: screen)

        let tucked = PetLayout.tuckedOrigin(
            edge: edge,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            anchorOrigin: targetExpandedOrigin
        )
        isDockTransitioning = true
        panel.bypassScreenConstraint = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(tucked)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.bypassScreenConstraint = false
                self.isDockTransitioning = false
                self.positionEdgePeek()
                self.edgePeekPanel.orderFrontRegardless()
            }
        }
    }

    private func restoreFromEdge(animated: Bool) {
        guard let edge = dockedEdge else { return }
        let screen = screenForEdgePeek() ?? screenForExpandedPet() ?? NSScreen.main
        guard let screen else { return }
        let target = PetLayout.expandedOrigin(
            edge: edge,
            previousOrigin: lastExpandedOrigin,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            allowedTopOverflow: panel.allowedTopOverflow
        )
        let tucked = PetLayout.tuckedOrigin(
            edge: edge,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            anchorOrigin: target
        )

        dockedEdge = nil
        UserDefaults.standard.removeObject(forKey: "petDockedEdge")
        edgePeekPanel.orderOut(nil)
        isDockTransitioning = true
        panel.bypassScreenConstraint = true
        panel.setFrameOrigin(tucked)
        panel.orderFrontRegardless()

        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.panel.bypassScreenConstraint = false
            self.isDockTransitioning = false
            self.lastExpandedOrigin = target
            self.persistExpandedOrigin()
            self.updateInteractionLock(self.store.interactionLocked)
        }

        guard animated else {
            panel.setFrameOrigin(target)
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(target)
        } completionHandler: {
            Task { @MainActor in finish() }
        }
    }

    private func positionEdgePeek(on providedScreen: NSScreen? = nil) {
        guard let edge = dockedEdge,
              let screen = providedScreen ?? screenForEdgePeek() ?? screenForExpandedPet() ?? NSScreen.main else {
            return
        }
        let anchor = CGRect(origin: lastExpandedOrigin, size: panel.frame.size)
        edgePeekPanel.setFrameOrigin(PetLayout.edgePeekOrigin(
            edge: edge,
            anchorFrame: anchor,
            visibleFrame: screen.visibleFrame,
            peekSize: edgePeekPanel.frame.size
        ))
    }

    private func resizeEdgePeekPanel() {
        let targetSize = PetLayout.edgePeekPanelSize(showsMiniStatus: store.shouldShowPetBubble)
        guard edgePeekPanel.frame.size != targetSize else { return }
        var frame = edgePeekPanel.frame
        frame.size = targetSize
        edgePeekPanel.setFrame(frame, display: true, animate: false)
    }

    private func refreshEdgePeekContent() {
        guard let edge = dockedEdge else { return }
        edgePeekPanel.contentView = NSHostingView(rootView: PetEdgePeekView(store: store, edge: edge) { [weak edgePeekPanel] in
            edgePeekPanel?.restoreAction?()
        })
    }

    private func persistExpandedOrigin() {
        let defaults = UserDefaults.standard
        defaults.set(lastExpandedOrigin.x, forKey: "petWindowX")
        defaults.set(lastExpandedOrigin.y, forKey: "petWindowY")
        defaults.set(true, forKey: "hasSavedPetWindowPosition")
    }

    private func screenAtMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) })
    }

    private func screenForExpandedPet() -> NSScreen? {
        let anchor = CGRect(origin: lastExpandedOrigin, size: panel.frame.size)
        return NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchor) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) })
    }

    private func screenForEdgePeek() -> NSScreen? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(edgePeekPanel.frame) })
    }
}
