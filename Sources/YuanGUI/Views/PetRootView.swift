import AppKit
import SwiftUI

struct PetRootView: View {
    let window: PetPanel
    let store: PetStore
    let chat: ChatStore
    let chatPresentation: ChatPresentationCoordinator
    let maintenance: MaintenanceStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation

    init(
        window: PetPanel,
        store: PetStore,
        chat: ChatStore,
        chatPresentation: ChatPresentationCoordinator,
        maintenance: MaintenanceStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation
    ) {
        self.window = window
        self.store = store
        self.chat = chat
        self.chatPresentation = chatPresentation
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        self.auxiliaryBubblePresentation = auxiliaryBubblePresentation
    }

    var body: some View {
        PetSceneRoot(
            window: window,
            store: store,
            chat: chat,
            chatPresentation: chatPresentation,
            maintenance: maintenance,
            focusTimer: focusTimer,
            music: music,
            auxiliaryBubblePresentation: auxiliaryBubblePresentation
        )
    }
}

private struct PetSceneRoot: View {
    @ObservedObject var window: PetPanel
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @ObservedObject var chatPresentation: ChatPresentationCoordinator
    @ObservedObject var maintenance: MaintenanceStore
    @ObservedObject var focusTimer: FocusTimerStore
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore
    @ObservedObject var auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation
    @Environment(\.appActions) private var appActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var dragStartOrigin: NSPoint?
    @State private var dragStartMouseLocation: NSPoint?
    @State private var sideControlsOnRight = false
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
        auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation
    ) {
        self.window = window
        self.store = store
        self.chat = chat
        self.chatPresentation = chatPresentation
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
        self.auxiliaryBubblePresentation = auxiliaryBubblePresentation
    }

    private enum SideTool: String {
        case role = "切换桌宠角色"
        case focus = "番茄钟"
        case cleanup = "空间清理"
        case uninstall = "软件卸载"
    }

    private var scale: CGFloat { store.petScale }
    private var panelSize: CGSize {
        PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: false,
            showsChat: chatPresentation.keepsExpandedLayout
        )
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
        ZStack(alignment: .bottom) {
            petLayer
            chatLayer
            sideControlLayer
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
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
        .onAppear { updateAdaptiveControlSide() }
        // AppKit changes the window frame atomically. Keep the root frame out
        // of SwiftUI's implicit animation system; only the chat and controls
        // layers below animate their own content.
        .animation(nil, value: panelSize)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.petScale)
        .animation(.easeOut(duration: 0.18), value: store.toast)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: window.dockCandidate
        )
        .contextMenu { contextMenu }
    }

    private var petLayer: some View {
        PetSpriteLayer(
            store: store,
            music: music,
            chatIsPresented: chatPresentation.keepsExpandedLayout,
            hasMaintenanceTask: maintenance.quickMode != nil,
            focusState: focusTimer.state,
            scale: scale,
            panelWidth: panelSize.width,
            displayedAction: displayedPetAction,
            dockPreviewScale: dockPreviewScale,
            dockPreviewOpacity: dockPreviewOpacity,
            dockPreviewRotation: dockPreviewRotation,
            dragStartOrigin: $dragStartOrigin,
            dragStartMouseLocation: $dragStartMouseLocation,
            updateAdaptiveControlSide: updateAdaptiveControlSide
        )
    }

    @ViewBuilder
    private var chatLayer: some View {
        PetChatLayer(
            chat: chat,
            pet: store,
            presentation: chatPresentation,
            maintenance: maintenance,
            scale: scale,
            reduceMotion: reduceMotion
        )
    }

    @ViewBuilder
    private var sideControlLayer: some View {
        Group {
            if store.isDropTargeted {
                dropOverlay
                    .transition(.scale.combined(with: .opacity))
            }

            if !store.isDropTargeted && !chatPresentation.keepsExpandedLayout {
                if hasActiveFocusCountdown {
                    focusModeSideControls
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading
                        )
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
                        if showsInteractiveSideControls {
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
                        }
                        if showsInteractiveSideControls {
                            focusSideButton(size: 40)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                                .padding(sideControlsOnRight ? .trailing : .leading, sideControlsPadding + 55)
                                .padding(.bottom, 98)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                                .zIndex(8)
                        }
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
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: chatPresentation.keepsExpandedLayout
        )
        .animation(.easeOut(duration: 0.14), value: hoveredSideTool)
    }

    private var displayedPetAction: PetAction {
        store.resolvedAction(isMusicPlaying: playback.isPlaying)
    }

    private var placesToolbarAbovePet: Bool {
        auxiliaryBubblePresentation.isVisible
            && auxiliaryBubblePresentation.placement == .belowPet
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
        // The side-control column stays compact so it cannot overlap the toolbar.
        // This label may extend into the transparent space beside the character.
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
                    .accessibilityLabel(
                        "\(AppLocalizer.string("专注中"))：\(focusTimer.timeText)"
                    )
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
        .help(hasActiveFocusCountdown
            ? "\(AppLocalizer.string("专注中"))：\(focusTimer.timeText)"
            : AppLocalizer.string("打开番茄钟"))
        .popover(isPresented: $showsFocusPopover, arrowEdge: sideControlsOnRight ? .trailing : .leading) {
            FocusTimerControlView(timer: focusTimer) { }
        }
    }

    private var showsTransientSideControls: Bool {
        isHovering || showsFocusPopover
    }

    private var showsInteractiveSideControls: Bool {
        showsTransientSideControls && !store.interactionLocked && !chatPresentation.keepsExpandedLayout
    }

    private var hasActiveFocusCountdown: Bool {
        focusTimer.state == .running || focusTimer.state == .paused
    }

    private var focusSideControlsPadding: CGFloat {
        PetLayout.usesCompactControls(scale: store.petScale)
            ? PetLayout.compactSideControlsInset + 8
            : sideControlsPadding + 40
    }

    private var sideControlsPadding: CGFloat {
        if sideControlsOnRight {
            return max(8, 72 * scale - 74)
        }
        return max(8, 142 * scale - 74)
    }

    private var maintenanceSideControls: some View {
        VStack(spacing: 3) {
            Button {
                startQuickCleanup()
            } label: {
                sideToolIcon("sparkles", tint: .mint, selected: maintenance.quickMode == .cleanup)
            }
            .buttonStyle(.plain)
            .onHover { setSideToolHover(.cleanup, hovering: $0) }
            .overlay { sideHoverLabel(for: .cleanup) }
            .help(AppLocalizer.string("空间清理：扫描可安全清理的缓存、日志和临时文件"))
            .offset(x: sideControlsOnRight ? 7 : -7)

            Button {
                startQuickUninstall()
            } label: {
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
        if hovering {
            hoveredSideTool = tool
        } else if hoveredSideTool == tool {
            hoveredSideTool = nil
        }
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

    @ViewBuilder
    private var contextMenu: some View {
        Button(chat.isPresented ? "收起 AI 对话" : "和元圭、VCC 聊天…") { appActions.open(.chat) }
        Button("打开完整监控") { appActions.open(.statusDashboard) }
        Button("打开清理屋…") { appActions.open(.maintenance(tab: 0)) }
        Button(store.shouldShowPetBubble ? "隐藏系统状态" : "显示系统状态") {
            store.toggleSystemStatus()
        }
        Button(store.desktopIconsVisible ? "隐藏桌面图标" : "显示桌面图标") {
            store.toggleDesktopIcons()
        }
        Menu("番茄钟") {
            switch focusTimer.state {
            case .idle, .completed:
                Button("开始 \(focusTimer.durationMinutes) 分钟专注") { focusTimer.start() }
                Divider()
                Button("15 分钟") { focusTimer.start(minutes: 15) }
                Button("25 分钟") { focusTimer.start(minutes: 25) }
                Button("45 分钟") { focusTimer.start(minutes: 45) }
                Button("60 分钟") { focusTimer.start(minutes: 60) }
            case .running:
                Button("暂停（剩余 \(focusTimer.timeText)）") { focusTimer.pause() }
                Button("提前结束") { focusTimer.stop() }
            case .paused:
                Button("继续（剩余 \(focusTimer.timeText)）") { focusTimer.resume() }
                Button("提前结束") { focusTimer.stop() }
            }
        }
        Menu("音乐") {
            Button("打开完整播放器…") { appActions.open(.music) }
            Button(music.playback.isPlaying ? "暂停" : "播放") { music.playPause() }
            Button("上一首") { music.previous() }
            Button("下一首") { music.next() }
            Divider()
            Button(music.lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词") { music.toggleLyricsVisible() }
        }
        Menu("切换角色") {
            ForEach(PetMode.allCases) { mode in
                Button(mode.title) { store.setMode(mode) }
            }
        }
        Menu("桌宠大小") {
            Button("迷你（50%）") { store.setPetScale(0.50) }
            Button("轻巧（60%）") { store.setPetScale(0.60) }
            Button("默认（75%）") { store.setPetScale(PetLayout.defaultScale) }
            Button("舒展（90%）") { store.setPetScale(0.90) }
            Button("大只（125%）") { store.setPetScale(1.25) }
            Button("超大（140%）") { store.setPetScale(1.40) }
        }
        Toggle("智能状态动作", isOn: Binding(
            get: { store.smartReactionsEnabled },
            set: { store.setSmartReactionsEnabled($0) }
        ))
        Button(store.interactionLocked ? "解锁桌宠点击" : "锁定并允许点击穿透") {
            store.toggleInteractionLock()
        }
        Button("设置…") { appActions.open(.settings(.pet)) }
        Divider()
        Button("打开废纸篓") { store.openTrash() }
        Button("清空废纸篓…") { store.confirmAndEmptyTrash() }
        Divider()
        Button("退出元圭与 VCC") { NSApp.terminate(nil) }
    }

    private func updateAdaptiveControlSide(for providedWindow: PetPanel? = nil) {
        guard let window = providedWindow ?? NSApp.windows.first(where: { $0 is PetPanel }) as? PetPanel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? window.screen
            ?? NSScreen.main
        guard let screen else { return }
        let petVisualCenterX = window.frame.midX + 35 * scale
        let shouldUseRight = petVisualCenterX < screen.visibleFrame.midX
        if sideControlsOnRight != shouldUseRight {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                sideControlsOnRight = shouldUseRight
            }
        }
    }

}

private struct PetChatLayer: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var pet: PetStore
    @ObservedObject var presentation: ChatPresentationCoordinator
    @ObservedObject var maintenance: MaintenanceStore
    let scale: CGFloat
    let reduceMotion: Bool

    @ViewBuilder
    var body: some View {
        if presentation.showsChatLayer {
            ZStack(alignment: .bottom) {
                if chat.latestReply != nil || chat.isSending || chat.errorMessage != nil {
                    PetReplyBubble(chat: chat, pet: pet)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 291 * scale + PetLayout.chatPetBottomInset + 4)
                        .zIndex(4)
                }

                if maintenance.quickMode == nil {
                    PetChatComposer(chat: chat, pet: pet)
                        .padding(.bottom, 3)
                        .zIndex(5)
                }
            }
            .opacity(presentation.showsChatContent ? 1 : 0)
            .scaleEffect(
                presentation.showsChatContent ? 1 : 0.97,
                anchor: .bottom
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: ChatPresentationCoordinator.contentAnimationDuration),
                value: presentation.showsChatContent
            )
        }
    }
}

private extension View {
    func controlPanel() -> some View {
        self.padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.3), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }
}
