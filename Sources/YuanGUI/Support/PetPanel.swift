import AppKit
import Combine
import QuartzCore
import SwiftUI

final class PetPanel: NSPanel {
    var allowedTopOverflow: CGFloat = 0
    var isUserDragging = false
    var bypassScreenConstraint = false
    var dragMovedAction: (() -> Void)?
    var dragEndedAction: (() -> Void)?
    var cancelAction: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if let cancelAction {
            cancelAction()
        } else {
            super.cancelOperation(sender)
        }
    }

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

private final class PetAuxiliaryBubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetPanelController {
    let panel: PetPanel
    private let store: PetStore
    private let chat: ChatStore
    private let maintenance: MaintenanceStore
    private let focusTimer: FocusTimerStore
    private let music: MusicFeature
    private let appActions: AppActions
    private let lockedToolbarPanel: PetLockedToolbarPanel
    private let auxiliaryBubblePanel: PetAuxiliaryBubblePanel
    private let auxiliaryBubblePresentation = PetAuxiliaryBubblePresentation()
    private let edgePeekPanel: PetEdgePeekPanel
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var dockedEdge: PetDockEdge?
    private var lastExpandedOrigin = CGPoint.zero
    private var isDockTransitioning = false
    private var lockedGlobalMouseMonitor: Any?
    private var lockedLocalMouseMonitor: Any?
    private var lockedHoverFallbackTimer: DispatchSourceTimer?
    private var lastLockedPointerInside = false
    private var layoutUpdateScheduled = false
    private var isApplyingProgrammaticLayout = false
    private var lastLayoutScale: Double
    private var lastLayoutShowsChat: Bool

    init(
        store: PetStore,
        chat: ChatStore,
        maintenance: MaintenanceStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        appActions: AppActions = .disabled
    ) {
        self.store = store
        self.chat = chat
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        self.appActions = appActions
        lastLayoutScale = store.petScale
        lastLayoutShowsChat = chat.isPresented
        let size = PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: false,
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
            contentRect: NSRect(origin: .zero, size: PetLayout.lockedControlPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        auxiliaryBubblePanel = PetAuxiliaryBubblePanel(
            contentRect: NSRect(
                origin: .zero,
                size: PetLayout.auxiliaryBubblePanelSize(scale: store.petScale)
            ),
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
        panel.contentView = NSHostingView(rootView:
            PetRootView(
                store: store,
                chat: chat,
                maintenance: maintenance,
                focusTimer: focusTimer,
                music: music,
                auxiliaryBubblePresentation: auxiliaryBubblePresentation
            )
                .environment(\.appActions, appActions)
        )
        panel.ignoresMouseEvents = store.interactionLocked
        updateAllowedTopOverflow()
        lockedToolbarPanel.isOpaque = false
        lockedToolbarPanel.backgroundColor = .clear
        lockedToolbarPanel.hasShadow = false
        lockedToolbarPanel.level = .floating
        lockedToolbarPanel.hidesOnDeactivate = false
        lockedToolbarPanel.isReleasedWhenClosed = false
        lockedToolbarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        lockedToolbarPanel.contentView = NSHostingView(rootView:
            PetUnlockControlView(store: store)
                .environment(\.appActions, appActions)
        )
        auxiliaryBubblePanel.isOpaque = false
        auxiliaryBubblePanel.backgroundColor = .clear
        auxiliaryBubblePanel.hasShadow = false
        auxiliaryBubblePanel.level = .floating
        auxiliaryBubblePanel.hidesOnDeactivate = false
        auxiliaryBubblePanel.isReleasedWhenClosed = false
        auxiliaryBubblePanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        auxiliaryBubblePanel.contentView = NSHostingView(rootView:
            PetAuxiliaryBubbleView(
                store: store,
                chat: chat,
                maintenance: maintenance,
                focusTimer: focusTimer,
                music: music,
                presentation: auxiliaryBubblePresentation
            )
            .environment(\.appActions, appActions)
        )
        panel.addChildWindow(auxiliaryBubblePanel, ordered: .above)
        edgePeekPanel.isOpaque = false
        edgePeekPanel.backgroundColor = .clear
        edgePeekPanel.hasShadow = false
        edgePeekPanel.level = .floating
        edgePeekPanel.hidesOnDeactivate = false
        edgePeekPanel.isReleasedWhenClosed = false
        edgePeekPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        edgePeekPanel.contentView = NSHostingView(rootView:
            PetEdgePeekView(store: store, edge: .left) { [weak peekPanel] in
                peekPanel?.restoreAction?()
            }
            .environment(\.appActions, appActions)
        )

        restoreOrPlaceWindow()
        lastExpandedOrigin = panel.frame.origin
        dockedEdge = UserDefaults.standard.string(forKey: "petDockedEdge").flatMap(PetDockEdge.init(rawValue:))
        panel.dragMovedAction = { [weak self] in
            self?.positionLockedToolbar()
            self?.positionAuxiliaryBubble()
        }
        panel.cancelAction = { [weak self] in
            guard let self, self.chat.isPresented else { return }
            self.chat.dismiss()
        }
        panel.dragEndedAction = { [weak self] in self?.finishUserDrag() }
        edgePeekPanel.restoreAction = { [weak self] in self?.restoreFromEdge(animated: true) }
        installObservers()
        Publishers.CombineLatest4(store.$showsSystemStatus, store.$smartState, store.$petScale, chat.$isPresented)
            .dropFirst()
            .sink { [weak self] _, _, _, _ in
                Task { @MainActor [weak self] in
                    self?.scheduleLayoutUpdate()
                    self?.updateAuxiliaryBubble()
                }
            }
            .store(in: &cancellables)
        store.$interactionLocked
            .removeDuplicates()
            .sink { [weak self] locked in
                // @Published emits from willSet. Defer until PetStore has
                // committed the new value, otherwise a newly started locked
                // hover tracker immediately sees the old `false` value and
                // shuts itself down.
                Task { @MainActor [weak self] in
                    guard let self, self.store.interactionLocked == locked else { return }
                    self.updateInteractionLock(locked)
                }
            }
            .store(in: &cancellables)
        store.$lockedControlsVisible
            .removeDuplicates()
            .sink { [weak self] visible in self?.updateLockedToolbarVisibility(visible: visible) }
            .store(in: &cancellables)
        maintenance.$quickMode
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleLayoutUpdate()
                    self?.updateAuxiliaryBubble()
                }
            }
            .store(in: &cancellables)
        store.$automaticBubbleSuppressed
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateAuxiliaryBubble() }
            }
            .store(in: &cancellables)
        store.$ambientMessage
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateAuxiliaryBubble() }
            }
            .store(in: &cancellables)
        Publishers.CombineLatest3(
            music.playback.$state,
            music.lyricsStore.$currentLine,
            music.lyricsPresentation.$lightSingAlongEnabled
        )
            .sink { [weak self] _, _, _ in Task { @MainActor [weak self] in self?.updateAuxiliaryBubble() } }
            .store(in: &cancellables)
        focusTimer.$state
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateAuxiliaryBubble() } }
            .store(in: &cancellables)
        store.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, self.auxiliaryBubblePanel.isVisible else { return }
                    self.positionAuxiliaryBubble()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let lockedGlobalMouseMonitor { NSEvent.removeMonitor(lockedGlobalMouseMonitor) }
        if let lockedLocalMouseMonitor { NSEvent.removeMonitor(lockedLocalMouseMonitor) }
        lockedHoverFallbackTimer?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func show() {
        if dockedEdge != nil {
            store.setPetPresented(false)
            panel.orderOut(nil)
            lockedToolbarPanel.orderOut(nil)
            refreshEdgePeekContent()
            resizeEdgePeekPanel()
            positionEdgePeek()
            edgePeekPanel.orderFrontRegardless()
            store.monitor.setPetVisible(true)
            return
        }
        constrainToVisibleScreens(persist: false)
        panel.orderFrontRegardless()
        updateAuxiliaryBubble()
        updateInteractionLock(store.interactionLocked)
        store.setPetPresented(true)
        store.monitor.setPetVisible(true)
    }

    func hide() {
        panel.orderOut(nil)
        lockedToolbarPanel.orderOut(nil)
        auxiliaryBubblePanel.orderOut(nil)
        edgePeekPanel.orderOut(nil)
        stopLockedHoverTracking()
        store.setPetPresented(false)
        store.monitor.setPetVisible(false)
    }

    func toggle() {
        (panel.isVisible || edgePeekPanel.isVisible) ? hide() : show()
    }

    func focusForChatInput() {
        if dockedEdge != nil {
            restoreFromEdge(animated: false)
        }
        // `@Published` presentation is delivered before SwiftUI completes its
        // update. Resize first so the composer never renders for one frame in
        // the old, smaller pet window.
        resizeToCurrentLayout()
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
                self.positionLockedToolbar()
                if self.auxiliaryBubblePanel.isVisible {
                    self.positionAuxiliaryBubble()
                }
                guard !self.panel.isUserDragging,
                      !self.isDockTransitioning,
                      !self.isApplyingProgrammaticLayout,
                      self.dockedEdge == nil else { return }
                self.lastExpandedOrigin = self.panel.frame.origin
                self.persistExpandedOrigin()
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

    private func scheduleLayoutUpdate() {
        guard !layoutUpdateScheduled else { return }
        layoutUpdateScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.layoutUpdateScheduled = false
            self.resizeToCurrentLayout()
        }
    }

    private func resizeToCurrentLayout() {
        let screen = screenForExpandedPet() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame
        let usableFrame = visibleFrame.map {
            PetLayout.usablePanelFrame(in: $0, showsChat: chat.isPresented)
        }
        var targetSize = PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: false,
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
        if let usableFrame {
            // Keep a fixed-width chat surface from extending past a narrow
            // display. SwiftUI will still lay out the controls inside the
            // available window instead of leaving the right/left side hidden.
            targetSize.width = min(targetSize.width, usableFrame.width)
            targetSize.height = min(targetSize.height, usableFrame.height)
        }
        updateAllowedTopOverflow()
        guard panel.frame.size != targetSize else {
            lastLayoutScale = store.petScale
            lastLayoutShowsChat = chat.isPresented
            updateAuxiliaryBubble()
            return
        }
        let fallbackVisibleFrame = CGRect(
            origin: panel.frame.origin,
            size: CGSize(
                width: max(panel.frame.width, targetSize.width),
                height: max(panel.frame.height, targetSize.height)
            )
        )
        let frame = PetLayout.resizedPanelFrame(
            from: panel.frame,
            targetSize: targetSize,
            scale: store.petScale,
            oldShowsChat: lastLayoutShowsChat,
            newShowsChat: chat.isPresented,
            visibleFrame: usableFrame ?? fallbackVisibleFrame
        )
        isApplyingProgrammaticLayout = true
        panel.bypassScreenConstraint = true
        panel.setFrame(frame, display: true, animate: false)
        panel.bypassScreenConstraint = false
        lastLayoutScale = store.petScale
        lastLayoutShowsChat = chat.isPresented
        if dockedEdge != nil {
            resizeEdgePeekPanel()
            positionEdgePeek()
            isApplyingProgrammaticLayout = false
            return
        }
        constrainToVisibleScreens(persist: false)
        positionLockedToolbar()
        updateAuxiliaryBubble()
        isApplyingProgrammaticLayout = false
    }

    private static func showsMusicLyric(store: PetStore, chat: ChatStore, maintenance: MaintenanceStore, focusTimer: FocusTimerStore, music: MusicFeature) -> Bool {
        music.playback.isPlaying && music.lyricsPresentation.lightSingAlongEnabled && music.lyricsStore.currentLine != nil
            && !chat.isPresented && maintenance.quickMode == nil
            && focusTimer.state != .running && focusTimer.state != .paused
    }

    private func restoreOrPlaceWindow() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "hasSavedPetWindowPosition") {
            panel.setFrameOrigin(NSPoint(
                x: defaults.double(forKey: "petWindowX"),
                y: defaults.double(forKey: "petWindowY")
            ))
            constrainToVisibleScreens(persist: false)
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

    private func constrainToVisibleScreens(persist: Bool = true) {
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
        let wasApplyingProgrammaticLayout = isApplyingProgrammaticLayout
        if !persist { isApplyingProgrammaticLayout = true }
        defer { isApplyingProgrammaticLayout = wasApplyingProgrammaticLayout }
        panel.setFrameOrigin(frame.origin)
        lastExpandedOrigin = frame.origin
        if persist { persistExpandedOrigin() }
        positionLockedToolbar()
        positionAuxiliaryBubble()
    }

    private func updateInteractionLock(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
        auxiliaryBubblePanel.ignoresMouseEvents = locked
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
        let placesAbovePet = auxiliaryBubblePanel.isVisible
            && auxiliaryBubblePresentation.placement == .belowPet
        let y = placesAbovePet
            ? panel.frame.maxY - lockedToolbarPanel.frame.height - PetLayout.bottomToolbarNormalBottomPadding
            : panel.frame.minY + (chat.isPresented
                ? PetLayout.bottomToolbarChatBottomPadding
                : PetLayout.bottomToolbarNormalBottomPadding)
        lockedToolbarPanel.setFrameOrigin(NSPoint(
            x: panel.frame.midX - lockedToolbarPanel.frame.width / 2,
            y: y
        ))
    }

    private func updateAuxiliaryBubble() {
        guard panel.isVisible, dockedEdge == nil, shouldShowAuxiliaryBubble else {
            auxiliaryBubblePresentation.isVisible = false
            auxiliaryBubblePanel.orderOut(nil)
            return
        }
        let size = PetLayout.auxiliaryBubblePanelSize(scale: store.petScale)
        if auxiliaryBubblePanel.frame.size != size {
            auxiliaryBubblePanel.setContentSize(size)
        }
        positionAuxiliaryBubble()
        auxiliaryBubblePresentation.isVisible = true
        auxiliaryBubblePanel.orderFrontRegardless()
    }

    private var shouldShowAuxiliaryBubble: Bool {
        guard maintenance.quickMode == nil, !chat.isPresented else { return false }
        return store.ambientMessage != nil
            || store.shouldShowPetBubble
            || Self.showsMusicLyric(
                store: store,
                chat: chat,
                maintenance: maintenance,
                focusTimer: focusTimer,
                music: music
            )
    }

    private func positionAuxiliaryBubble() {
        let performanceStart = RuntimePerformance.start()
        defer { RuntimePerformance.record("pet.auxiliary.position", since: performanceStart) }
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
            ?? panel.screen
            ?? screenForExpandedPet()
            ?? NSScreen.main else { return }
        let spriteFrame = PetLayout.petVisualFrame(
            panelFrame: panel.frame,
            scale: store.petScale,
            showsChat: chat.isPresented
        )
        let action = store.resolvedAction(isMusicPlaying: music.playback.isPlaying)
        let visiblePetFrame = PetLayout.visiblePetFrame(
            spriteFrame: spriteFrame,
            normalizedVisibleBounds: SpriteLoader.normalizedVisibleBounds(mode: store.mode, action: action)
        )
        let layout = PetLayout.auxiliaryBubbleLayout(
            petVisualFrame: visiblePetFrame,
            bubbleSize: auxiliaryBubblePanel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        auxiliaryBubblePresentation.placement = layout.placement
        auxiliaryBubblePanel.setFrameOrigin(layout.origin)
        positionLockedToolbar()
    }

    private func startLockedHoverTracking() {
        lastLockedPointerInside = false
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if lockedGlobalMouseMonitor == nil {
            lockedGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                Task { @MainActor [weak self] in self?.lockedMouseEventReceived() }
            }
        }
        if lockedLocalMouseMonitor == nil {
            lockedLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                Task { @MainActor [weak self] in self?.lockedMouseEventReceived() }
                return event
            }
        }
        // Mouse movement is event-driven during normal operation, so a locked
        // and stationary pet creates no periodic wakeups. Only fall back to a
        // low-frequency pointer check if macOS could not create the global
        // monitor at all.
        if lockedGlobalMouseMonitor == nil {
            ensureLockedHoverFallback()
        } else {
            lockedHoverFallbackTimer?.cancel()
            lockedHoverFallbackTimer = nil
        }
        pollLockedPointer()
    }

    private func ensureLockedHoverFallback() {
        guard lockedHoverFallbackTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.pollLockedPointer() }
        lockedHoverFallbackTimer = timer
        timer.resume()
    }

    private func lockedMouseEventReceived() {
        pollLockedPointer()
    }

    private func stopLockedHoverTracking() {
        if let lockedGlobalMouseMonitor { NSEvent.removeMonitor(lockedGlobalMouseMonitor) }
        if let lockedLocalMouseMonitor { NSEvent.removeMonitor(lockedLocalMouseMonitor) }
        lockedGlobalMouseMonitor = nil
        lockedLocalMouseMonitor = nil
        lockedHoverFallbackTimer?.cancel()
        lockedHoverFallbackTimer = nil
    }

    private func pollLockedPointer() {
        guard store.interactionLocked else {
            stopLockedHoverTracking()
            return
        }
        guard panel.isVisible, dockedEdge == nil else { return }
        let location = NSEvent.mouseLocation
        let inside = isPointerInsideLockedRegion(at: location)

        if inside {
            store.revealLockedControls()
            // The published flag and the auxiliary window can become out of
            // sync after a resize or a transient visibility change. Repair the
            // actual window as well, even when the flag was already true.
            if !lastLockedPointerInside || !lockedToolbarPanel.isVisible {
                updateLockedToolbarVisibility(visible: true)
            }
        } else if !inside, lastLockedPointerInside {
            store.scheduleLockedControlsHide(after: 1)
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
            showsBubble: false,
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
        stopLockedHoverTracking()
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
        auxiliaryBubblePanel.orderOut(nil)
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
                self.store.setPetPresented(false)
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
            self.store.setPetPresented(true)
            self.updateInteractionLock(self.store.interactionLocked)
            self.updateAuxiliaryBubble()
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
        edgePeekPanel.contentView = NSHostingView(rootView:
            PetEdgePeekView(store: store, edge: edge) { [weak edgePeekPanel] in
                edgePeekPanel?.restoreAction?()
            }
            .environment(\.appActions, appActions)
        )
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
