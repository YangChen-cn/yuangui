import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PetSceneInteractiveLayer: View {
    let window: PetPanel
    let store: PetStore
    let chat: ChatStore
    let chatPresentation: ChatPresentationCoordinator
    let maintenance: MaintenanceStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var sideControlsOnRight = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PetSpriteLayer(
                window: window,
                store: store,
                chatPresentation: chatPresentation,
                maintenance: maintenance,
                focusTimer: focusTimer,
                music: music,
                updateAdaptiveControlSide: updateAdaptiveControlSide
            )
            PetChatLayer(
                chat: chat,
                pet: store,
                presentation: chatPresentation,
                maintenance: maintenance,
                reduceMotion: reduceMotion
            )
            PetSideControlsLayer(
                window: window,
                store: store,
                chat: chat,
                chatPresentation: chatPresentation,
                maintenance: maintenance,
                focusTimer: focusTimer,
                music: music,
                auxiliaryBubblePresentation: auxiliaryBubblePresentation,
                isHovering: $isHovering,
                sideControlsOnRight: $sideControlsOnRight
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: chatPresentation.keepsExpandedLayout
        )
    }

    private func updateAdaptiveControlSide(_ providedWindow: PetPanel? = nil) {
        let window = providedWindow ?? self.window
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? window.screen
            ?? NSScreen.main
        guard let screen else { return }
        let petVisualCenterX = window.frame.midX + 35 * CGFloat(store.petScale)
        let shouldUseRight = petVisualCenterX < screen.visibleFrame.midX
        guard sideControlsOnRight != shouldUseRight else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            sideControlsOnRight = shouldUseRight
        }
    }
}

struct PetSpriteLayer: View {
    @ObservedObject var window: PetPanel
    @ObservedObject var store: PetStore
    @ObservedObject var chatPresentation: ChatPresentationCoordinator
    @ObservedObject private var playback: MusicPlaybackStore
    let maintenance: MaintenanceStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let updateAdaptiveControlSide: (PetPanel?) -> Void

    @State private var dragStartOrigin: NSPoint?
    @State private var dragStartMouseLocation: NSPoint?

    init(
        window: PetPanel,
        store: PetStore,
        chatPresentation: ChatPresentationCoordinator,
        maintenance: MaintenanceStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        updateAdaptiveControlSide: @escaping (PetPanel?) -> Void
    ) {
        self.window = window
        self.store = store
        self.chatPresentation = chatPresentation
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        self.updateAdaptiveControlSide = updateAdaptiveControlSide
        _playback = ObservedObject(wrappedValue: music.playback)
    }

    private var scale: CGFloat { CGFloat(store.petScale) }
    private var panelWidth: CGFloat {
        PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: false,
            showsChat: chatPresentation.keepsExpandedLayout
        ).width
    }
    private var displayedAction: PetAction {
        store.resolvedAction(isMusicPlaying: playback.isPlaying)
    }
    private var dockPreviewScale: CGFloat {
        guard let candidate = window.dockCandidate else { return 1 }
        return candidate.isCommitReady ? 0.95 : 0.98
    }
    private var dockPreviewOpacity: Double {
        window.dockCandidate?.isCommitReady == true ? 0.90 : 1
    }
    private var dockPreviewRotation: Angle {
        guard let candidate = window.dockCandidate else { return .zero }
        switch candidate.edge {
        case .left: return .degrees(-2)
        case .right: return .degrees(2)
        case .top, .bottom: return .zero
        }
    }

    var body: some View {
        VStack(spacing: -12) {
            if let toast = store.toast {
                PetToastView(message: toast, maximumWidth: max(220, panelWidth - 24))
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .zIndex(3)
            }

            AnimatedPetSprite(
                mode: store.presentationMode,
                action: displayedAction,
                motionEnabled: store.isPetPresented,
                sequencePlaybackEnabled: store.petMotionEnabled
                    && (!displayedAction.file.contains("chatting") || store.ambientMessage != nil)
            )
            .overlay(alignment: .topTrailing) {
                PetMusicIndicatorLayer(
                    music: music,
                    chatPresentation: chatPresentation,
                    maintenance: maintenance,
                    focusTimer: focusTimer,
                    scale: scale
                )
            }
            .frame(width: 326 * scale, height: 326 * scale)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
            .scaleEffect(dockPreviewScale)
            .rotationEffect(dockPreviewRotation)
            .opacity(dockPreviewOpacity)
            .contentShape(Rectangle())
            .onTapGesture { store.interact() }
            .simultaneousGesture(windowDragGesture)
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $store.isDropTargeted,
                perform: handleDrop
            )
        }
        .frame(maxWidth: .infinity)
        .offset(x: 35 * scale)
        .padding(.bottom, chatPresentation.keepsExpandedLayout ? PetLayout.chatPetBottomInset : 0)
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { _ in
                guard let window = NSApp.windows.first(where: { $0 is PetPanel }) as? PetPanel else { return }
                if dragStartOrigin == nil {
                    window.isUserDragging = true
                    dragStartOrigin = window.frame.origin
                    dragStartMouseLocation = NSEvent.mouseLocation
                }
                guard let origin = dragStartOrigin,
                      let mouseOrigin = dragStartMouseLocation else { return }
                let mouse = NSEvent.mouseLocation
                window.setFrameOrigin(NSPoint(
                    x: origin.x + mouse.x - mouseOrigin.x,
                    y: origin.y + mouse.y - mouseOrigin.y
                ))
                window.dragMovedAction?()
                updateAdaptiveControlSide(window)
            }
            .onEnded { _ in
                if let window = NSApp.windows.first(where: { $0 is PetPanel }) as? PetPanel {
                    window.isUserDragging = false
                    updateAdaptiveControlSide(window)
                    window.dragEndedAction?()
                }
                dragStartOrigin = nil
                dragStartMouseLocation = nil
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !matching.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in matching {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? NSURL {
                    url = itemURL as URL
                } else {
                    url = nil
                }
                guard let url else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) { self.store.recycle(urls) }
        return true
    }
}

private struct PetMusicIndicatorLayer: View {
    let music: MusicFeature
    @ObservedObject var chatPresentation: ChatPresentationCoordinator
    @ObservedObject var maintenance: MaintenanceStore
    @ObservedObject var focusTimer: FocusTimerStore
    let scale: CGFloat

    var body: some View {
        PetMusicIndicatorView(
            music: music,
            isChatPresented: chatPresentation.keepsExpandedLayout,
            hasMaintenanceTask: maintenance.quickMode != nil,
            focusState: focusTimer.state,
            scale: scale
        )
    }
}

private struct PetSideControlsLayer: View {
    private enum SideTool: String {
        case role = "切换桌宠角色"
        case focus = "番茄钟"
        case cleanup = "空间清理"
        case uninstall = "软件卸载"
    }

    let window: PetPanel
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @ObservedObject var chatPresentation: ChatPresentationCoordinator
    @ObservedObject var maintenance: MaintenanceStore
    @ObservedObject var focusTimer: FocusTimerStore
    let music: MusicFeature
    @ObservedObject var auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation
    @Binding var isHovering: Bool
    @Binding var sideControlsOnRight: Bool

    @ObservedObject private var playback: MusicPlaybackStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredSideTool: SideTool?
    @State private var showsFocusPopover = false
    @State private var isMiniPlayerPresented = false

    init(
        window: PetPanel,
        store: PetStore,
        chat: ChatStore,
        chatPresentation: ChatPresentationCoordinator,
        maintenance: MaintenanceStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation,
        isHovering: Binding<Bool>,
        sideControlsOnRight: Binding<Bool>
    ) {
        self.window = window
        self.store = store
        self.chat = chat
        self.chatPresentation = chatPresentation
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        self.auxiliaryBubblePresentation = auxiliaryBubblePresentation
        _isHovering = isHovering
        _sideControlsOnRight = sideControlsOnRight
        _playback = ObservedObject(wrappedValue: music.playback)
    }

    private var scale: CGFloat { CGFloat(store.petScale) }
    private var hasActiveFocusCountdown: Bool {
        focusTimer.state == .running || focusTimer.state == .paused
    }
    private var showsTransientSideControls: Bool {
        isHovering || showsFocusPopover
    }
    private var showsInteractiveSideControls: Bool {
        showsTransientSideControls && !store.interactionLocked && !chatPresentation.keepsExpandedLayout
    }
    private var placesToolbarAbovePet: Bool {
        auxiliaryBubblePresentation.isVisible
            && auxiliaryBubblePresentation.placement == .belowPet
    }
    private var focusSideControlsPadding: CGFloat {
        PetLayout.usesCompactControls(scale: store.petScale)
            ? PetLayout.compactSideControlsInset + 8
            : sideControlsPadding + 40
    }
    private var sideControlsPadding: CGFloat {
        sideControlsOnRight ? max(8, 72 * scale - 74) : max(8, 142 * scale - 74)
    }

    var body: some View {
        Group {
            if store.isDropTargeted {
                dropOverlay
                    .transition(.scale.combined(with: .opacity))
            }

            if !store.isDropTargeted && !chatPresentation.keepsExpandedLayout {
                if hasActiveFocusCountdown {
                    focusModeSideControls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                        .padding(sideControlsOnRight ? .trailing : .leading, focusSideControlsPadding)
                        .padding(.bottom, PetLayout.usesCompactControls(scale: store.petScale) ? 8 : 36)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .zIndex(8)
                } else if showsInteractiveSideControls {
                    if PetLayout.usesCompactControls(scale: store.petScale) {
                        compactSideControls
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                            .padding(sideControlsOnRight ? .trailing : .leading, PetLayout.compactSideControlsInset + 8)
                            .padding(.bottom, 8)
                            .transition(.move(edge: sideControlsOnRight ? .trailing : .leading).combined(with: .opacity))
                            .zIndex(8)
                    } else {
                        roleControls
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                            .padding(sideControlsOnRight ? .trailing : .leading, sideControlsPadding + 20)
                            .padding(.bottom, 143)
                            .transition(.move(edge: sideControlsOnRight ? .trailing : .leading).combined(with: .opacity))
                        maintenanceSideControls
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                            .padding(sideControlsOnRight ? .trailing : .leading, sideControlsPadding + 50)
                            .padding(.bottom, 22)
                            .transition(.scale(scale: 0.82).combined(with: .opacity))
                        focusSideButton(size: 40)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                            .padding(sideControlsOnRight ? .trailing : .leading, sideControlsPadding + 55)
                            .padding(.bottom, 98)
                            .transition(.scale(scale: 0.82).combined(with: .opacity))
                            .zIndex(8)
                    }
                }
                if !hasActiveFocusCountdown && !store.interactionLocked && (isHovering || isMiniPlayerPresented) {
                    PetBottomControlLayer(
                        store: store,
                        chat: chat,
                        music: music,
                        isMiniPlayerPresented: $isMiniPlayerPresented
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: placesToolbarAbovePet ? .top : .bottom
                    )
                    .padding(.top, placesToolbarAbovePet ? 6 : 0)
                    .padding(.bottom, placesToolbarAbovePet ? 0 : 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear { updateAdaptiveControlSide() }
        .onChange(of: store.interactionLocked) { _, locked in
            if locked {
                isHovering = false
                isMiniPlayerPresented = false
            }
        }
        .onChange(of: focusTimer.state) { _, state in
            guard state == .running || state == .paused else { return }
            showsFocusPopover = false
            isHovering = false
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: chatPresentation.keepsExpandedLayout)
        .animation(.easeOut(duration: 0.14), value: hoveredSideTool)
    }

    private var roleControls: some View {
        Menu {
            ForEach(PetMode.allCases) { mode in
                Button {
                    store.setMode(mode)
                } label: {
                    if store.mode == mode { Label(mode.title, systemImage: "checkmark") }
                    else { Text(mode.title) }
                }
            }
        } label: {
            Text(store.mode.title)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 76, height: 26)
        .onHover { setSideToolHover(.role, hovering: $0) }
        .overlay { sideHoverLabel(for: .role) }
        .help(AppLocalizer.string("切换桌宠角色"))
    }

    private var compactSideControls: some View {
        VStack(spacing: 4) {
            roleControls
                .opacity(showsInteractiveSideControls ? 1 : 0)
                .allowsHitTesting(showsInteractiveSideControls)
            focusSideButton(size: 34)
                .offset(x: sideControlsOnRight ? -7 : 7)
            Button { startQuickCleanup() } label: {
                sideToolIcon("sparkles", tint: .mint, selected: maintenance.quickMode == .cleanup, size: 30)
            }
            .buttonStyle(.plain)
            .onHover { setSideToolHover(.cleanup, hovering: $0) }
            .overlay { sideHoverLabel(for: .cleanup) }
            .help(AppLocalizer.string("空间清理"))
            .opacity(showsInteractiveSideControls ? 1 : 0)
            .allowsHitTesting(showsInteractiveSideControls)
            Button { startQuickUninstall() } label: {
                sideToolIcon("shippingbox", tint: .blue, selected: maintenance.quickMode == .uninstall, size: 30)
            }
            .buttonStyle(.plain)
            .onHover { setSideToolHover(.uninstall, hovering: $0) }
            .overlay { sideHoverLabel(for: .uninstall) }
            .help(AppLocalizer.string("软件卸载"))
            .opacity(showsInteractiveSideControls ? 1 : 0)
            .allowsHitTesting(showsInteractiveSideControls)
        }
        .frame(width: PetLayout.compactSideControlsWidth)
    }

    private var focusModeSideControls: some View {
        VStack(spacing: 5) {
            if store.interactionLocked {
                FocusCountdownBadge(timer: focusTimer)
                    .accessibilityLabel("\(AppLocalizer.string("专注中"))：\(focusTimer.timeText)")
            } else {
                focusSideButton(size: 34)
            }
            if !store.interactionLocked {
                Button { isMiniPlayerPresented.toggle() } label: {
                    sideToolIcon("music.note", tint: .purple, selected: playback.isPlaying, size: 30)
                }
                .buttonStyle(.plain)
                .help(AppLocalizer.string("打开迷你播放器"))
                .accessibilityLabel(AppLocalizer.string("打开迷你播放器"))
                .popover(isPresented: $isMiniPlayerPresented, arrowEdge: sideControlsOnRight ? .trailing : .leading) {
                    MiniMusicPlayerView(music: music)
                }
                Button { store.toggleInteractionLock() } label: {
                    sideToolIcon("lock.open.fill", tint: .orange, selected: false, size: 30)
                }
                .buttonStyle(.plain)
                .help(AppLocalizer.string("锁定并允许穿透"))
                .accessibilityLabel(AppLocalizer.string("锁定并允许穿透"))
            }
        }
        .frame(width: 40)
    }

    private func focusSideButton(size: CGFloat) -> some View {
        Button { showsFocusPopover.toggle() } label: {
            if hasActiveFocusCountdown {
                FocusCountdownBadge(timer: focusTimer, size: size)
            } else {
                FocusIdleBadge(size: size)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!store.interactionLocked)
        .onHover { setSideToolHover(.focus, hovering: $0) }
        .overlay { sideHoverLabel(for: .focus) }
        .help(hasActiveFocusCountdown ? "\(AppLocalizer.string("专注中"))：\(focusTimer.timeText)" : AppLocalizer.string("打开番茄钟"))
        .popover(isPresented: $showsFocusPopover, arrowEdge: sideControlsOnRight ? .trailing : .leading) {
            FocusTimerControlView(timer: focusTimer) { }
        }
    }

    private var maintenanceSideControls: some View {
        VStack(spacing: 3) {
            Button { startQuickCleanup() } label: {
                sideToolIcon("sparkles", tint: .mint, selected: maintenance.quickMode == .cleanup)
            }
            .buttonStyle(.plain)
            .onHover { setSideToolHover(.cleanup, hovering: $0) }
            .overlay { sideHoverLabel(for: .cleanup) }
            .help(AppLocalizer.string("空间清理：扫描可安全清理的缓存、日志和临时文件"))
            .offset(x: sideControlsOnRight ? 7 : -7)
            Button { startQuickUninstall() } label: {
                sideToolIcon("shippingbox", tint: .blue, selected: maintenance.quickMode == .uninstall)
            }
            .buttonStyle(.plain)
            .onHover { setSideToolHover(.uninstall, hovering: $0) }
            .overlay { sideHoverLabel(for: .uninstall) }
            .help(AppLocalizer.string("软件卸载：查找应用及其可确认的用户级残留"))
            .offset(x: sideControlsOnRight ? -7 : 7)
        }
        .animation(.easeOut(duration: 0.14), value: hoveredSideTool)
    }

    @ViewBuilder
    private func sideHoverLabel(for tool: SideTool) -> some View {
        if hoveredSideTool == tool {
            PetHoverLabel(text: tool.rawValue)
                .offset(x: sideControlsOnRight ? -70 : 70)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(12)
        }
    }

    private func setSideToolHover(_ tool: SideTool, hovering: Bool) {
        if hovering { hoveredSideTool = tool }
        else if hoveredSideTool == tool { hoveredSideTool = nil }
    }

    private func startQuickCleanup() {
        chat.dismiss()
        Task { await maintenance.startQuickCleanup() }
    }

    private func startQuickUninstall() {
        chat.dismiss()
        Task { await maintenance.startQuickUninstall() }
    }

    private func sideToolIcon(_ systemName: String, tint: Color, selected: Bool, size: CGFloat = 34) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(selected ? Color.white : tint)
            .frame(width: size, height: size)
            .background(selected ? tint : Color.white.opacity(0.76), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.15), radius: 7, y: 3)
            .contentShape(Circle())
    }

    private var dropOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .pink)
            Text("松手移入废纸篓")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 278, height: 216)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.5), lineWidth: 1))
        .padding(.bottom, 58)
    }

    private func updateAdaptiveControlSide() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? window.screen
            ?? NSScreen.main
        guard let screen else { return }
        let petVisualCenterX = window.frame.midX + 35 * scale
        let shouldUseRight = petVisualCenterX < screen.visibleFrame.midX
        guard sideControlsOnRight != shouldUseRight else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            sideControlsOnRight = shouldUseRight
        }
    }
}
