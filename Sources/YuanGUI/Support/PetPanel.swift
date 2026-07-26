import AppKit
import Combine
import QuartzCore
import SwiftUI

final class PetPanel: NSPanel, ObservableObject {
    @Published private(set) var dockCandidate: PetDockCandidate?
    var allowedTopOverflow: CGFloat = 0
    var allowedLeftOverflow: CGFloat = 0
    var allowedRightOverflow: CGFloat = 0
    var isUserDragging = false
    var bypassScreenConstraint = false
    var dragMovedAction: (() -> Void)?
    var dragEndedAction: (() -> Void)?
    var cancelAction: (() -> Void)?

    func setDockCandidate(_ candidate: PetDockCandidate?) {
        guard dockCandidate?.edge != candidate?.edge
            || dockCandidate?.isCommitReady != candidate?.isCommitReady else {
            return
        }
        dockCandidate = candidate
    }

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
            allowedTopOverflow: allowedTopOverflow,
            allowedLeftOverflow: allowedLeftOverflow,
            allowedRightOverflow: allowedRightOverflow
        )
        return frame
    }
}

@MainActor
final class PetDockPreviewPresentation: ObservableObject {
    @Published var edge: PetDockEdge = .left
    @Published var isCommitReady = false
}

private final class PetEdgePeekPanel: NSPanel {
    var restoreAction: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class PetDockPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class PetEdgeStatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
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
    static let auxiliaryBubbleCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary
    ]

    let panel: PetPanel
    private let store: PetStore
    private let chat: ChatStore
    private let maintenance: MaintenanceStore
    private let focusTimer: FocusTimerStore
    private let music: MusicFeature
    private let appActions: AppActions
    private var lockedToolbarPanel: PetLockedToolbarPanel?
    private var auxiliaryBubblePanel: PetAuxiliaryBubblePanel?
    private let auxiliaryBubblePresentation = PetAuxiliaryBubblePresentation()
    private var edgePeekPanel: PetEdgePeekPanel?
    private var edgeStatusPanel: PetEdgeStatusPanel?
    private var dockPreviewPanel: PetDockPreviewPanel?
    private let dockPreviewPresentation = PetDockPreviewPresentation()
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
    private var preChatPanelOrigin: CGPoint?
    private var edgePeekHovering = false
    private var edgePeekAutoExposed = false
    private var edgeMessage: String?
    private var edgeMessageHideTask: Task<Void, Never>?
    private var edgeAutoPeekTask: Task<Void, Never>?
    private var auxiliaryBubbleUnloadTask: Task<Void, Never>?
    private var edgePeekUnloadTask: Task<Void, Never>?
    private var lastPresentedEdgeSmartState: SmartPetState?
    private var edgeTransitionGeneration: UInt = 0

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
                window: panel,
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
        restoreOrPlaceWindow()
        lastExpandedOrigin = panel.frame.origin
        dockedEdge = UserDefaults.standard.string(forKey: "petDockedEdge").flatMap(PetDockEdge.init(rawValue:))
        if dockedEdge != nil {
            _ = ensureEdgePeekPanel()
        }
        panel.dragMovedAction = { [weak self] in
            self?.updateDockPreview()
            self?.positionLockedToolbar()
            self?.positionAuxiliaryBubble()
        }
        panel.cancelAction = { [weak self] in
            guard let self, self.chat.isPresented else { return }
            self.chat.dismiss()
        }
        panel.dragEndedAction = { [weak self] in self?.finishUserDrag() }
        chat.onWillPresentationChange = { [weak self] presented in
            self?.prepareForChatPresentationChange(presented)
        }
        installObservers()
        Publishers.CombineLatest4(store.$showsSystemStatus, store.$smartState, store.$petScale, chat.$isPresented)
            .dropFirst()
            .sink { [weak self] _, smartState, _, _ in
                Task { @MainActor [weak self] in
                    self?.scheduleLayoutUpdate()
                    self?.updateAuxiliaryBubble()
                    self?.updateEdgeStatusPanel()
                    self?.presentEdgeSmartState(smartState)
                }
            }
            .store(in: &cancellables)
        store.$urgentReminderPulseVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                guard visible else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.store.smartState.isUrgent else { return }
                    self.presentEdgeSmartState(self.store.smartState, force: true)
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
                    guard let self, self.auxiliaryBubblePanel?.isVisible == true else { return }
                    self.positionAuxiliaryBubble()
                }
            }
            .store(in: &cancellables)
        store.$mode
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await Task.yield()
                    guard self.dockedEdge != nil else { return }
                    if self.isDockTransitioning {
                        self.cancelEdgeTransition()
                        self.panel.orderOut(nil)
                        self.store.setPetPresented(false)
                    }
                    self.refreshEdgePeekContent()
                    self.resizeEdgePeekPanel()
                    self.positionEdgePeek()
                    self.edgePeekPanel?.alphaValue = 1
                    self.edgePeekPanel?.orderFrontRegardless()
                    self.updateEdgeStatusPanel()
                    self.presentEdgeSmartState(self.store.smartState, force: true)
                }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    private func ensureLockedToolbarPanel() -> PetLockedToolbarPanel {
        if let lockedToolbarPanel { return lockedToolbarPanel }
        let toolbarPanel = PetLockedToolbarPanel(
            contentRect: NSRect(origin: .zero, size: PetLayout.lockedControlPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.isOpaque = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.hasShadow = false
        toolbarPanel.level = .floating
        toolbarPanel.hidesOnDeactivate = false
        toolbarPanel.isReleasedWhenClosed = false
        toolbarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toolbarPanel.contentView = NSHostingView(rootView:
            PetUnlockControlView(store: store)
                .environment(\.appActions, appActions)
        )
        lockedToolbarPanel = toolbarPanel
        return toolbarPanel
    }

    @discardableResult
    private func ensureAuxiliaryBubblePanel() -> PetAuxiliaryBubblePanel {
        auxiliaryBubbleUnloadTask?.cancel()
        auxiliaryBubbleUnloadTask = nil
        if let auxiliaryBubblePanel { return auxiliaryBubblePanel }
        let bubblePanel = PetAuxiliaryBubblePanel(
            contentRect: NSRect(
                origin: .zero,
                size: PetLayout.auxiliaryBubblePanelSize(scale: store.petScale)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        bubblePanel.isOpaque = false
        bubblePanel.backgroundColor = .clear
        bubblePanel.hasShadow = false
        bubblePanel.level = .floating
        bubblePanel.hidesOnDeactivate = false
        bubblePanel.isReleasedWhenClosed = false
        bubblePanel.collectionBehavior = Self.auxiliaryBubbleCollectionBehavior
        bubblePanel.contentView = NSHostingView(rootView:
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
        panel.addChildWindow(bubblePanel, ordered: .above)
        auxiliaryBubblePanel = bubblePanel
        return bubblePanel
    }

    @discardableResult
    private func ensureEdgePeekPanel() -> PetEdgePeekPanel? {
        guard let edge = dockedEdge else { return nil }
        edgePeekUnloadTask?.cancel()
        edgePeekUnloadTask = nil
        if let edgePeekPanel { return edgePeekPanel }
        let peekPanel = PetEdgePeekPanel(
            contentRect: NSRect(origin: .zero, size: PetLayout.edgePeekSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        peekPanel.isOpaque = false
        peekPanel.backgroundColor = .clear
        peekPanel.hasShadow = false
        peekPanel.level = .floating
        peekPanel.hidesOnDeactivate = false
        peekPanel.isReleasedWhenClosed = false
        peekPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        peekPanel.contentView = NSHostingView(rootView:
            PetEdgePeekView(store: store, edge: edge, hoveringChanged: nil) { [weak peekPanel] in
                peekPanel?.restoreAction?()
            }
            .environment(\.appActions, appActions)
        )
        peekPanel.restoreAction = { [weak self] in self?.restoreFromEdge(animated: true) }
        edgePeekPanel = peekPanel
        return peekPanel
    }

    @discardableResult
    private func ensureEdgeStatusPanel() -> PetEdgeStatusPanel {
        if let edgeStatusPanel { return edgeStatusPanel }
        let statusPanel = PetEdgeStatusPanel(
            contentRect: NSRect(origin: .zero, size: PetLayout.edgeStatusSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        statusPanel.isOpaque = false
        statusPanel.backgroundColor = .clear
        statusPanel.hasShadow = false
        statusPanel.level = .floating
        statusPanel.ignoresMouseEvents = true
        statusPanel.hidesOnDeactivate = false
        statusPanel.isReleasedWhenClosed = false
        statusPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        edgeStatusPanel = statusPanel
        return statusPanel
    }

    @discardableResult
    private func ensureDockPreviewPanel() -> PetDockPreviewPanel {
        if let dockPreviewPanel { return dockPreviewPanel }
        let previewPanel = PetDockPreviewPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 5, height: 180)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        previewPanel.isOpaque = false
        previewPanel.backgroundColor = .clear
        previewPanel.hasShadow = false
        previewPanel.level = .floating
        previewPanel.ignoresMouseEvents = true
        previewPanel.hidesOnDeactivate = false
        previewPanel.isReleasedWhenClosed = false
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        previewPanel.contentView = NSHostingView(rootView:
            PetDockPreviewView(presentation: dockPreviewPresentation)
        )
        dockPreviewPanel = previewPanel
        return previewPanel
    }

    private func unloadDockPreviewPanel() {
        dockPreviewPanel?.orderOut(nil)
        dockPreviewPanel?.contentView = nil
        dockPreviewPanel = nil
    }

    private func unloadEdgeStatusPanel() {
        edgeStatusPanel?.orderOut(nil)
        edgeStatusPanel?.contentView = nil
        edgeStatusPanel = nil
    }

    private func unloadEdgePeekPanel() {
        edgePeekPanel?.orderOut(nil)
        edgePeekPanel?.restoreAction = nil
        edgePeekPanel?.contentView = nil
        edgePeekPanel = nil
    }

    private func unloadAuxiliaryBubblePanel() {
        guard let bubblePanel = auxiliaryBubblePanel else { return }
        bubblePanel.orderOut(nil)
        panel.removeChildWindow(bubblePanel)
        bubblePanel.contentView = nil
        auxiliaryBubblePanel = nil
        auxiliaryBubblePresentation.isVisible = false
    }

    private func scheduleAuxiliaryBubbleUnload() {
        guard auxiliaryBubblePanel != nil else { return }
        auxiliaryBubbleUnloadTask?.cancel()
        auxiliaryBubbleUnloadTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.auxiliaryBubbleUnloadTask = nil
            guard self.auxiliaryBubblePanel?.isVisible != true else { return }
            self.unloadAuxiliaryBubblePanel()
        }
    }

    private func scheduleEdgePeekPanelUnload() {
        guard edgePeekPanel != nil else { return }
        edgePeekUnloadTask?.cancel()
        edgePeekUnloadTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.edgePeekUnloadTask = nil
            guard self.dockedEdge == nil, !self.isDockTransitioning else { return }
            self.unloadEdgePeekPanel()
        }
    }

    deinit {
        if let lockedGlobalMouseMonitor { NSEvent.removeMonitor(lockedGlobalMouseMonitor) }
        if let lockedLocalMouseMonitor { NSEvent.removeMonitor(lockedLocalMouseMonitor) }
        lockedHoverFallbackTimer?.cancel()
        edgeMessageHideTask?.cancel()
        edgeAutoPeekTask?.cancel()
        auxiliaryBubbleUnloadTask?.cancel()
        edgePeekUnloadTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func show() {
        if dockedEdge != nil {
            store.setPetPresented(false)
            panel.orderOut(nil)
            lockedToolbarPanel?.orderOut(nil)
            refreshEdgePeekContent()
            resizeEdgePeekPanel()
            positionEdgePeek()
            edgePeekPanel?.orderFrontRegardless()
            edgePeekPanel?.alphaValue = 1
            updateEdgeStatusPanel()
            presentEdgeSmartState(store.smartState, force: true)
            store.monitor.setPetVisible(true)
            return
        }
        constrainToVisibleScreens(
            persist: true,
            maximumHorizontalOverflow: PetLayout.restoredPanelHorizontalOverflow
        )
        panel.orderFrontRegardless()
        updateAuxiliaryBubble()
        updateInteractionLock(store.interactionLocked)
        store.setPetPresented(true)
        store.monitor.setPetVisible(true)
    }

    func hide() {
        resetEdgePresentation()
        panel.orderOut(nil)
        lockedToolbarPanel?.orderOut(nil)
        auxiliaryBubblePanel?.orderOut(nil)
        scheduleAuxiliaryBubbleUnload()
        edgePeekPanel?.orderOut(nil)
        edgeStatusPanel?.orderOut(nil)
        unloadDockPreviewPanel()
        stopLockedHoverTracking()
        store.setPetPresented(false)
        store.monitor.setPetVisible(false)
    }

    func toggle() {
        (panel.isVisible || edgePeekPanel?.isVisible == true) ? hide() : show()
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

    private func prepareForChatPresentationChange(_ willPresent: Bool) {
        guard willPresent else { return }
        if dockedEdge != nil {
            restoreFromEdge(animated: false)
        }
        // This runs before ChatStore publishes the new value, so neither
        // SwiftUI's intrinsic-content update nor AppKit's panel resizing can
        // replace the true compact origin with the expanded chat origin.
        preChatPanelOrigin = panel.frame.origin
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Handle this synchronously. NSWindow posts the notification
                // during setFrame; deferring to a task can outlive the
                // programmatic-layout guard and persist a temporary position.
                let wasProgrammaticMove = self.isApplyingProgrammaticLayout
                self.positionLockedToolbar()
                if self.auxiliaryBubblePanel?.isVisible == true {
                    self.positionAuxiliaryBubble()
                }
                guard !self.panel.isUserDragging,
                      !self.isDockTransitioning,
                      !wasProgrammaticMove,
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
        let isOpeningChat = !lastLayoutShowsChat && chat.isPresented
        let isClosingChat = lastLayoutShowsChat && !chat.isPresented
        if isOpeningChat, preChatPanelOrigin == nil {
            // Keep the exact compact-panel position. Preserving only the
            // sprite frame loses information when the larger chat panel is
            // clamped at a display edge and causes a visible jump on close.
            preChatPanelOrigin = panel.frame.origin
        }
        updateAllowedTopOverflow()
        let mustRestoreChatOrigin = isClosingChat && preChatPanelOrigin != nil
        guard panel.frame.size != targetSize || mustRestoreChatOrigin else {
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
        let layoutFrame = usableFrame ?? fallbackVisibleFrame
        let frame: CGRect
        if isClosingChat, let originalOrigin = preChatPanelOrigin {
            frame = CGRect(
                origin: PetLayout.restoredCompactOrigin(
                    originalOrigin,
                    panelSize: targetSize,
                    scale: store.petScale,
                    visibleFrame: layoutFrame,
                ),
                size: targetSize
            )
        } else {
            frame = PetLayout.resizedPanelFrame(
                from: panel.frame,
                targetSize: targetSize,
                scale: store.petScale,
                oldShowsChat: lastLayoutShowsChat,
                newShowsChat: chat.isPresented,
                visibleFrame: layoutFrame
            )
        }
        isApplyingProgrammaticLayout = true
        panel.bypassScreenConstraint = true
        panel.setFrame(frame, display: true, animate: false)
        panel.bypassScreenConstraint = false
        lastLayoutScale = store.petScale
        lastLayoutShowsChat = chat.isPresented
        if isClosingChat {
            preChatPanelOrigin = nil
        }
        if dockedEdge != nil {
            resizeEdgePeekPanel()
            positionEdgePeek()
            isApplyingProgrammaticLayout = false
            return
        }
        if !isClosingChat {
            constrainToVisibleScreens(persist: false)
        }
        if isClosingChat {
            lastExpandedOrigin = panel.frame.origin
            persistExpandedOrigin()
        }
        positionLockedToolbar()
        updateAuxiliaryBubble()
        isApplyingProgrammaticLayout = false
    }

    private static func showsMusicLyric(store: PetStore, chat: ChatStore, maintenance: MaintenanceStore, focusTimer: FocusTimerStore, music: MusicFeature) -> Bool {
        PetMusicPresentationPolicy.showsLyricBubble(
            isPlaying: music.playback.isPlaying,
            lightSingAlongEnabled: music.lyricsPresentation.lightSingAlongEnabled,
            hasCurrentLyric: music.lyricsStore.currentLine != nil,
            isChatPresented: chat.isPresented,
            hasMaintenanceTask: maintenance.quickMode != nil,
            focusState: focusTimer.state
        )
    }

    private func restoreOrPlaceWindow() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "hasSavedPetWindowPosition") {
            panel.setFrameOrigin(NSPoint(
                x: defaults.double(forKey: "petWindowX"),
                y: defaults.double(forKey: "petWindowY")
            ))
            constrainToVisibleScreens(
                persist: false,
                maximumHorizontalOverflow: PetLayout.restoredPanelHorizontalOverflow
            )
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

    private func constrainToVisibleScreens(
        persist: Bool = true,
        maximumHorizontalOverflow: CGFloat? = nil
    ) {
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
            allowedTopOverflow: panel.allowedTopOverflow,
            allowedLeftOverflow: maximumHorizontalOverflow.map {
                min(panel.allowedLeftOverflow, $0)
            } ?? panel.allowedLeftOverflow,
            allowedRightOverflow: maximumHorizontalOverflow.map {
                min(panel.allowedRightOverflow, $0)
            } ?? panel.allowedRightOverflow
        )
        let wasApplyingProgrammaticLayout = isApplyingProgrammaticLayout
        if !persist { isApplyingProgrammaticLayout = true }
        defer { isApplyingProgrammaticLayout = wasApplyingProgrammaticLayout }
        panel.setFrameOrigin(frame.origin)
        if persist {
            lastExpandedOrigin = frame.origin
            persistExpandedOrigin()
        }
        positionLockedToolbar()
        positionAuxiliaryBubble()
    }

    private func updateInteractionLock(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
        auxiliaryBubblePanel?.ignoresMouseEvents = locked
        guard locked, panel.isVisible, dockedEdge == nil else {
            stopLockedHoverTracking()
            lockedToolbarPanel?.orderOut(nil)
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
            lockedToolbarPanel?.orderOut(nil)
            return
        }
        let toolbarPanel = ensureLockedToolbarPanel()
        positionLockedToolbar()
        toolbarPanel.orderFrontRegardless()
    }

    private func positionLockedToolbar() {
        guard let toolbarPanel = lockedToolbarPanel else { return }
        let placesAbovePet = auxiliaryBubblePanel?.isVisible == true
            && auxiliaryBubblePresentation.placement == .belowPet
        let y = placesAbovePet
            ? panel.frame.maxY - toolbarPanel.frame.height - PetLayout.bottomToolbarNormalBottomPadding
            : panel.frame.minY + (chat.isPresented
                ? PetLayout.bottomToolbarChatBottomPadding
                : PetLayout.bottomToolbarNormalBottomPadding)
        toolbarPanel.setFrameOrigin(NSPoint(
            x: panel.frame.midX - toolbarPanel.frame.width / 2,
            y: y
        ))
    }

    private func updateAuxiliaryBubble() {
        guard panel.isVisible, dockedEdge == nil, shouldShowAuxiliaryBubble else {
            auxiliaryBubblePresentation.isVisible = false
            auxiliaryBubblePanel?.orderOut(nil)
            scheduleAuxiliaryBubbleUnload()
            return
        }
        auxiliaryBubbleUnloadTask?.cancel()
        auxiliaryBubbleUnloadTask = nil
        let bubblePanel = ensureAuxiliaryBubblePanel()
        let size = PetLayout.auxiliaryBubblePanelSize(scale: store.petScale)
        if bubblePanel.frame.size != size {
            bubblePanel.setContentSize(size)
        }
        positionAuxiliaryBubble()
        auxiliaryBubblePresentation.isVisible = true
        bubblePanel.orderFrontRegardless()
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
        guard let bubblePanel = auxiliaryBubblePanel else { return }
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
            bubbleSize: bubblePanel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        auxiliaryBubblePresentation.placement = layout.placement
        bubblePanel.setFrameOrigin(layout.origin)
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
            if !lastLockedPointerInside || lockedToolbarPanel?.isVisible != true {
                updateLockedToolbarVisibility(visible: true)
            }
        } else if !inside, lastLockedPointerInside {
            store.scheduleLockedControlsHide(after: 1)
        }
        lastLockedPointerInside = inside
    }

    private func isPointerInsideLockedRegion(at location: CGPoint) -> Bool {
        let petArea = panel.frame.insetBy(dx: -8, dy: -8)
        let toolbarArea = lockedToolbarPanel?.frame.insetBy(dx: -8, dy: -8)
        return petArea.contains(location) || toolbarArea?.contains(location) == true
    }

    private func updateAllowedTopOverflow() {
        panel.allowedTopOverflow = PetLayout.allowedTopOverflow(
            scale: store.petScale,
            showsBubble: false,
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
        let allowsCompactOverflow = !chat.isPresented && maintenance.quickMode == nil
        let horizontalOverflow = PetLayout.compactHorizontalOverflow(scale: store.petScale)
        panel.allowedLeftOverflow = allowsCompactOverflow ? horizontalOverflow.left : 0
        panel.allowedRightOverflow = allowsCompactOverflow ? horizontalOverflow.right : 0
    }

    private func finishUserDrag() {
        guard !isDockTransitioning else { return }
        let screen = screenAtMouse() ?? screenForExpandedPet()
        guard let screen else { return }
        let visiblePetFrame = currentVisiblePetFrame()
        let candidate = PetLayout.dockingCandidate(
            for: visiblePetFrame,
            in: screen.visibleFrame,
            threshold: PetLayout.dockCommitThreshold,
            allowedEdges: PetLayout.defaultDockEdges
        )
        panel.setDockCandidate(nil)
        unloadDockPreviewPanel()
        if let edge = candidate?.edge, candidate?.isCommitReady == true {
            dock(to: edge, on: screen)
        } else {
            if chat.isPresented {
                let petVisualFrame = PetLayout.petVisualFrame(
                    panelFrame: panel.frame,
                    scale: store.petScale,
                    showsChat: chat.isPresented
                )
                let compactSize = PetLayout.panelSize(
                    scale: store.petScale,
                    showsBubble: false,
                    showsChat: false,
                    showsMaintenance: maintenance.quickMode != nil
                )
                let compactOrigin = PetLayout.panelOrigin(
                    preservingPetVisualFrame: petVisualFrame,
                    targetPanelSize: compactSize,
                    scale: store.petScale,
                    showsChat: false
                )
                preChatPanelOrigin = PetLayout.constrainedOrigin(
                    compactOrigin,
                    panelSize: compactSize,
                    visibleFrame: screen.visibleFrame,
                    allowedTopOverflow: PetLayout.compactTopTransparentInset * store.petScale
                )
            }
            lastExpandedOrigin = panel.frame.origin
            persistExpandedOrigin()
            positionLockedToolbar()
        }
    }

    private func dock(to edge: PetDockEdge, on screen: NSScreen) {
        guard dockedEdge == nil else { return }
        let transitionGeneration = beginEdgeTransition()
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
        edgePeekHovering = false
        edgePeekAutoExposed = false
        lastPresentedEdgeSmartState = nil
        UserDefaults.standard.set(edge.rawValue, forKey: "petDockedEdge")
        persistExpandedOrigin()
        lockedToolbarPanel?.orderOut(nil)
        auxiliaryBubblePanel?.orderOut(nil)
        scheduleAuxiliaryBubbleUnload()
        unloadEdgeStatusPanel()
        edgePeekUnloadTask?.cancel()
        edgePeekUnloadTask = nil
        guard let peekPanel = ensureEdgePeekPanel() else { return }
        refreshEdgePeekContent()
        resizeEdgePeekPanel()
        positionEdgePeek(on: screen)

        let tucked = tuckedPanelOrigin(
            edge: edge,
            expandedOrigin: targetExpandedOrigin,
            visibleFrame: screen.visibleFrame
        )
        panel.bypassScreenConstraint = true
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        peekPanel.alphaValue = 0
        peekPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducesMotion ? 0.18 : 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            if !reducesMotion {
                panel.animator().setFrameOrigin(tucked)
            }
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.edgeTransitionGeneration == transitionGeneration,
                      self.dockedEdge == edge else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.bypassScreenConstraint = false
                self.isDockTransitioning = false
                self.store.setPetPresented(false)
                self.positionEdgePeek()
                self.edgePeekPanel?.alphaValue = 1
                self.presentEdgeSmartState(self.store.smartState, force: true)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard let self,
                  self.edgeTransitionGeneration == transitionGeneration,
                  self.isDockTransitioning,
                  self.dockedEdge == edge else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.edgePeekPanel?.animator().alphaValue = 1
            } completionHandler: {}
        }
    }

    private func restoreFromEdge(animated: Bool) {
        guard let edge = dockedEdge else { return }
        let screen = screenForEdgePeek() ?? screenForExpandedPet() ?? NSScreen.main
        guard let screen else { return }
        let proposedTarget = PetLayout.expandedOrigin(
            edge: edge,
            previousOrigin: lastExpandedOrigin,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            allowedTopOverflow: panel.allowedTopOverflow
        )
        var edgeAdjustedTarget = proposedTarget
        switch edge {
        case .left:
            edgeAdjustedTarget.x -= PetLayout.restoredPanelHorizontalOverflow
        case .right:
            edgeAdjustedTarget.x += PetLayout.restoredPanelHorizontalOverflow
        case .top, .bottom:
            break
        }
        let target = expandedPanelOriginEnsuringPetVisible(
            edgeAdjustedTarget,
            visibleFrame: screen.visibleFrame
        )
        let tucked = tuckedPanelOrigin(
            edge: edge,
            expandedOrigin: target,
            visibleFrame: screen.visibleFrame
        )
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let transitionGeneration = beginEdgeTransition()
        dockedEdge = nil
        resetEdgePresentation()
        UserDefaults.standard.removeObject(forKey: "petDockedEdge")
        unloadEdgeStatusPanel()
        scheduleEdgePeekPanelUnload()
        panel.bypassScreenConstraint = true
        panel.setFrameOrigin(reducesMotion ? target : tucked)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        edgeStatusPanel?.orderOut(nil)
        edgePeekPanel?.alphaValue = 1
        edgePeekPanel?.orderFrontRegardless()
        store.setPetPresented(true)

        let finish: @MainActor () -> Void = { [weak self] in
            guard let self,
                  self.edgeTransitionGeneration == transitionGeneration,
                  self.dockedEdge == nil else { return }
            let finalOrigin = PetLayout.constrainedOrigin(
                target,
                panelSize: self.panel.frame.size,
                visibleFrame: screen.visibleFrame,
                allowedTopOverflow: self.panel.allowedTopOverflow,
                allowedLeftOverflow: edge == .left
                    ? PetLayout.restoredPanelHorizontalOverflow
                    : 0,
                allowedRightOverflow: edge == .right
                    ? PetLayout.restoredPanelHorizontalOverflow
                    : 0
            )
            self.isApplyingProgrammaticLayout = true
            self.panel.bypassScreenConstraint = true
            self.panel.setFrameOrigin(finalOrigin)
            self.panel.bypassScreenConstraint = false
            self.isDockTransitioning = false
            self.isApplyingProgrammaticLayout = false
            self.lastExpandedOrigin = finalOrigin
            self.persistExpandedOrigin()
            self.updateInteractionLock(self.store.interactionLocked)
            self.updateAuxiliaryBubble()
        }

        guard animated else {
            panel.setFrameOrigin(target)
            edgePeekPanel?.orderOut(nil)
            panel.alphaValue = 1
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducesMotion ? 0.18 : 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !reducesMotion {
                panel.animator().setFrameOrigin(target)
            }
            panel.animator().alphaValue = 1
        } completionHandler: {
            Task { @MainActor in finish() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(135))
            guard let self,
                  self.edgeTransitionGeneration == transitionGeneration,
                  self.isDockTransitioning,
                  self.dockedEdge == nil else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.edgePeekPanel?.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor [weak self] in self?.edgePeekPanel?.orderOut(nil) }
            }
        }
    }

    private func beginEdgeTransition() -> UInt {
        cancelEdgeTransition()
        edgeTransitionGeneration &+= 1
        isDockTransitioning = true
        return edgeTransitionGeneration
    }

    private func cancelEdgeTransition() {
        edgeTransitionGeneration &+= 1
        panel.setFrameOrigin(panel.frame.origin)
        panel.alphaValue = 1
        panel.bypassScreenConstraint = false
        edgePeekPanel?.alphaValue = 0
        edgePeekPanel?.orderOut(nil)
        edgeStatusPanel?.orderOut(nil)
        isDockTransitioning = false
    }

    private func positionEdgePeek(on providedScreen: NSScreen? = nil) {
        guard let edge = dockedEdge,
              let peekPanel = edgePeekPanel,
              let screen = providedScreen ?? screenForEdgePeek() ?? screenForExpandedPet() ?? NSScreen.main else {
            return
        }
        let anchor = CGRect(origin: lastExpandedOrigin, size: panel.frame.size)
        peekPanel.setFrameOrigin(PetLayout.edgePeekOrigin(
            edge: edge,
            anchorFrame: anchor,
            visibleFrame: screen.visibleFrame,
            peekSize: peekPanel.frame.size,
            exposedWidth: (edgePeekHovering || edgePeekAutoExposed)
                ? PetLayout.edgePeekHoverExposedWidth
                : PetLayout.edgePeekExposedWidth
        ))
        if edgeStatusPanel?.isVisible == true {
            positionEdgeStatusPanel(on: screen)
        }
    }

    private func resizeEdgePeekPanel() {
        guard let peekPanel = edgePeekPanel else { return }
        let targetSize = PetLayout.edgePeekSize
        guard peekPanel.frame.size != targetSize else { return }
        var frame = peekPanel.frame
        frame.size = targetSize
        peekPanel.setFrame(frame, display: true, animate: false)
    }

    private func refreshEdgePeekContent() {
        guard let edge = dockedEdge, let peekPanel = ensureEdgePeekPanel() else { return }
        peekPanel.contentView = NSHostingView(rootView:
            PetEdgePeekView(
                store: store,
                edge: edge,
                hoveringChanged: { [weak self] hovering in
                    guard let self else { return }
                    self.edgePeekHoverDidChange(hovering)
                }
            ) { [weak edgePeekPanel] in
                edgePeekPanel?.restoreAction?()
            }
            .environment(\.appActions, appActions)
        )
        if edgeStatusPanel != nil { refreshEdgeStatusContent() }
    }

    private func updateEdgeStatusPanel() {
        guard dockedEdge != nil, edgePeekPanel?.isVisible == true else {
            edgeStatusPanel?.orderOut(nil)
            return
        }
        let isPeekExposed = edgePeekHovering || edgePeekAutoExposed
        let showsMonitor = store.showsSystemStatus && isPeekExposed
        guard showsMonitor || edgeMessage != nil else {
            edgeStatusPanel?.orderOut(nil)
            return
        }
        refreshEdgeStatusContent()
        positionEdgeStatusPanel()
        edgeStatusPanel?.orderFrontRegardless()
    }

    private func refreshEdgeStatusContent() {
        let statusPanel = ensureEdgeStatusPanel()
        let targetSize: CGSize
        if store.showsSystemStatus && (edgePeekHovering || edgePeekAutoExposed) {
            targetSize = edgeMessage == nil
                ? PetLayout.edgeStatusSize
                : PetLayout.edgeStatusMessageSize
            statusPanel.contentView = NSHostingView(rootView:
                PetEdgeMiniStatusView(store: store, message: edgeMessage)
            )
        } else if let edgeMessage {
            targetSize = PetLayout.edgeMessageSize
            statusPanel.contentView = NSHostingView(rootView:
                PetEdgeMessageBubbleView(message: edgeMessage)
            )
        } else {
            targetSize = PetLayout.edgeStatusSize
            statusPanel.contentView = NSHostingView(rootView:
                PetEdgeMiniStatusView(store: store)
            )
        }
        guard statusPanel.frame.size != targetSize else { return }
        var frame = statusPanel.frame
        frame.size = targetSize
        statusPanel.setFrame(frame, display: true, animate: false)
    }

    private func positionEdgeStatusPanel(on providedScreen: NSScreen? = nil) {
        guard let edge = dockedEdge,
              let statusPanel = edgeStatusPanel,
              let peekPanel = edgePeekPanel,
              let screen = providedScreen ?? screenForEdgePeek() ?? screenForExpandedPet() ?? NSScreen.main else {
            return
        }
        let visibleFrame = screen.visibleFrame
        let size = statusPanel.frame.size
        let y = min(
            max(peekPanel.frame.midY - size.height / 2, visibleFrame.minY),
            visibleFrame.maxY - size.height
        )
        let x: CGFloat
        switch edge {
        case .left:
            x = visibleFrame.minX + PetLayout.edgePeekHoverExposedWidth + PetLayout.edgeStatusGap
        case .right:
            x = visibleFrame.maxX - PetLayout.edgePeekHoverExposedWidth
                - PetLayout.edgeStatusGap - size.width
        case .top, .bottom:
            return
        }
        statusPanel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func edgePeekHoverDidChange(_ hovering: Bool) {
        edgePeekHovering = hovering
        positionEdgePeek()
        updateEdgeStatusPanel()
    }

    private func presentEdgeSmartState(_ state: SmartPetState, force: Bool = false) {
        guard dockedEdge != nil,
              edgePeekPanel?.isVisible == true,
              store.smartReactionsEnabled else {
            return
        }
        if state == .normal {
            lastPresentedEdgeSmartState = nil
            return
        }
        guard state.showsAutomaticBubble,
              force || lastPresentedEdgeSmartState != state else {
            return
        }
        lastPresentedEdgeSmartState = state
        showEdgeMessage(
            PetEdgeMessageResolver.alert(
                for: store.mode,
                state: state,
                snapshot: store.monitor.snapshot
            ),
            autoExpose: true
        )
    }

    private func showEdgeMessage(_ message: String, autoExpose: Bool = false) {
        guard dockedEdge != nil, edgePeekPanel?.isVisible == true else { return }
        edgeMessageHideTask?.cancel()
        edgeMessage = message
        if autoExpose {
            edgeAutoPeekTask?.cancel()
            edgePeekAutoExposed = true
            positionEdgePeek()
            edgeAutoPeekTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1_350))
                guard !Task.isCancelled, let self else { return }
                self.edgePeekAutoExposed = false
                self.positionEdgePeek()
                self.updateEdgeStatusPanel()
            }
        }
        updateEdgeStatusPanel()
        edgeMessageHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.edgeMessage = nil
            self.updateEdgeStatusPanel()
        }
    }

    private func resetEdgePresentation() {
        edgePeekHovering = false
        edgePeekAutoExposed = false
        edgeMessage = nil
        lastPresentedEdgeSmartState = nil
        edgeMessageHideTask?.cancel()
        edgeMessageHideTask = nil
        edgeAutoPeekTask?.cancel()
        edgeAutoPeekTask = nil
    }

    private func tuckedPanelOrigin(
        edge: PetDockEdge,
        expandedOrigin: CGPoint,
        visibleFrame: CGRect
    ) -> CGPoint {
        let panelFrame = CGRect(origin: expandedOrigin, size: panel.frame.size)
        let spriteFrame = PetLayout.petVisualFrame(
            panelFrame: panelFrame,
            scale: store.petScale,
            showsChat: chat.isPresented
        )
        let visiblePetFrame = PetLayout.visiblePetFrame(
            spriteFrame: spriteFrame,
            normalizedVisibleBounds: SpriteLoader.normalizedVisibleBounds(
                mode: store.mode,
                action: store.resolvedAction(isMusicPlaying: music.playback.isPlaying)
            )
        )
        return PetLayout.tuckedOrigin(
            edge: edge,
            panelOrigin: expandedOrigin,
            visiblePetFrame: visiblePetFrame,
            visibleFrame: visibleFrame
        )
    }

    private func expandedPanelOriginEnsuringPetVisible(
        _ proposedOrigin: CGPoint,
        visibleFrame: CGRect
    ) -> CGPoint {
        let panelFrame = CGRect(origin: proposedOrigin, size: panel.frame.size)
        let spriteFrame = PetLayout.petVisualFrame(
            panelFrame: panelFrame,
            scale: store.petScale,
            showsChat: chat.isPresented
        )
        return PetLayout.originEnsuringContentVisible(
            panelOrigin: proposedOrigin,
            contentFrame: spriteFrame,
            visibleFrame: visibleFrame,
            inset: PetLayout.restoredPetScreenInset
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

    private func currentVisiblePetFrame() -> CGRect {
        let spriteFrame = PetLayout.petVisualFrame(
            panelFrame: panel.frame,
            scale: store.petScale,
            showsChat: chat.isPresented
        )
        return PetLayout.visiblePetFrame(
            spriteFrame: spriteFrame,
            normalizedVisibleBounds: SpriteLoader.normalizedVisibleBounds(
                mode: store.mode,
                action: store.resolvedAction(isMusicPlaying: music.playback.isPlaying)
            )
        )
    }

    private func updateDockPreview() {
        guard panel.isUserDragging,
              let screen = screenAtMouse() ?? screenForExpandedPet() else {
            panel.setDockCandidate(nil)
            unloadDockPreviewPanel()
            return
        }
        let candidate = PetLayout.dockingCandidate(
            for: currentVisiblePetFrame(),
            in: screen.visibleFrame,
            allowedEdges: PetLayout.defaultDockEdges
        )
        panel.setDockCandidate(candidate)
        guard let candidate else {
            unloadDockPreviewPanel()
            return
        }
        let previewPanel = ensureDockPreviewPanel()
        dockPreviewPresentation.edge = candidate.edge
        dockPreviewPresentation.isCommitReady = candidate.isCommitReady
        let frame = dockPreviewFrame(for: candidate.edge, petFrame: currentVisiblePetFrame(), screen: screen)
        previewPanel.setFrame(frame, display: true, animate: false)
        previewPanel.orderFrontRegardless()
    }

    private func dockPreviewFrame(for edge: PetDockEdge, petFrame: CGRect, screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let length = min(220, max(120, petFrame.height * 0.58))
        let y = min(max(petFrame.midY - length / 2, visible.minY + 18), visible.maxY - length - 18)
        switch edge {
        case .left:
            return CGRect(x: visible.minX, y: y, width: 5, height: length)
        case .right:
            return CGRect(x: visible.maxX - 5, y: y, width: 5, height: length)
        case .top, .bottom:
            return .zero
        }
    }

    private func screenForExpandedPet() -> NSScreen? {
        let anchor = CGRect(origin: lastExpandedOrigin, size: panel.frame.size)
        return NSScreen.screens.first(where: { $0.visibleFrame.intersects(anchor) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) })
    }

    private func screenForEdgePeek() -> NSScreen? {
        guard let edgePeekPanel else { return nil }
        return NSScreen.screens.first(where: { $0.visibleFrame.intersects(edgePeekPanel.frame) })
    }
}
