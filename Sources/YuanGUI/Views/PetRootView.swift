import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PetRootView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @ObservedObject var maintenance: MaintenanceStore
    @ObservedObject var focusTimer: FocusTimerStore
    @ObservedMusicFeature var music: MusicFeature
    @Environment(\.appActions) private var appActions
    @State private var isHovering = false
    @State private var dragStartOrigin: NSPoint?
    @State private var dragStartMouseLocation: NSPoint?
    @State private var sideControlsOnRight = false
    @State private var hoveredSideTool: SideTool?
    @State private var showsFocusPopover = false
    @State private var isMiniPlayerPresented = false

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
            showsChat: chat.isPresented,
            showsMaintenance: maintenance.quickMode != nil
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if maintenance.quickMode != nil {
                PetMaintenanceBubble(store: maintenance)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 291 * scale + 4)
                    .zIndex(6)
            } else if chat.isPresented {
                if chat.latestReply != nil || chat.isSending || chat.errorMessage != nil {
                    PetReplyBubble(chat: chat, pet: store)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 291 * scale + 62)
                        .zIndex(4)
                }
            }

            VStack(spacing: -12) {
                if let toast = store.toast {
                    Text(toast)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .zIndex(3)
                }

                AnimatedPetSprite(
                    mode: store.mode,
                    action: displayedPetAction,
                    motionEnabled: store.isPetPresented,
                    sequencePlaybackEnabled: store.petMotionEnabled
                        && (!displayedPetAction.file.contains("chatting") || store.ambientMessage != nil)
                )
                    .overlay(alignment: .topTrailing) {
                        if music.playback.isPlaying {
                            Image(systemName: "music.note")
                                .font(.system(size: max(14, 24 * scale), weight: .bold))
                                .foregroundStyle(.pink)
                                .padding(6)
                                .background(.regularMaterial, in: Circle())
                                .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: music.lyricsPresentation.lightSingAlongEnabled)
                                .accessibilityLabel("音乐播放中")
                        }
                    }
                    .frame(width: 326 * scale, height: 326 * scale)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.interact()
                    }
                    .simultaneousGesture(windowDragGesture)
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $store.isDropTargeted) { providers in
                        handleDrop(providers)
                    }
            }
            .frame(maxWidth: .infinity)
            .offset(x: 35 * scale)
            .padding(.bottom, chat.isPresented ? 58 : 0)

            if chat.isPresented && maintenance.quickMode == nil {
                PetChatComposer(chat: chat, pet: store)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            if store.isDropTargeted {
                dropOverlay
                    .transition(.scale.combined(with: .opacity))
            }

            if !store.isDropTargeted {
                if showsInteractiveSideControls || hasActiveFocusCountdown {
                    if PetLayout.usesCompactControls(scale: store.petScale), !chat.isPresented {
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
                                .padding(.bottom, chat.isPresented ? 173 : 143)
                                .transition(.move(edge: sideControlsOnRight ? .trailing : .leading).combined(with: .opacity))
                            maintenanceSideControls
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                                .padding(sideControlsOnRight ? .trailing : .leading, sideControlsPadding + 50)
                                .padding(.bottom, chat.isPresented ? 64 : 22)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                        }
                        if showsInteractiveSideControls || hasActiveFocusCountdown {
                            focusSideButton(size: 40)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideControlsOnRight ? .bottomTrailing : .bottomLeading)
                                .padding(sideControlsOnRight ? .trailing : .leading, sideControlsPadding + 55)
                                .padding(.bottom, chat.isPresented ? 128 : 98)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                                .zIndex(8)
                        }
                    }
                }
                if !store.interactionLocked && (isHovering || isMiniPlayerPresented) {
                    PetBottomControlsView(
                        store: store,
                        chat: chat,
                        music: music,
                        isMiniPlayerPresented: $isMiniPlayerPresented
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, chat.isPresented ? 70 : 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .onChange(of: store.interactionLocked) { _, locked in
            if locked { isHovering = false }
        }
        .onAppear { updateAdaptiveControlSide() }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: chat.isPresented)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.petScale)
        .animation(.easeOut(duration: 0.18), value: store.toast)
        .contextMenu { contextMenu }
    }

    private var displayedPetAction: PetAction {
        store.resolvedAction(isMusicPlaying: music.playback.isPlaying)
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
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .frame(width: 42, height: 24)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .menuStyle(.borderlessButton)
        .frame(width: PetLayout.compactSideControlsWidth, height: 26)
        .onHover { setSideToolHover(.role, hovering: $0) }
        .overlay { sideHoverLabel(for: .role) }
        .help("切换桌宠角色")
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
            .help("空间清理")
            .opacity(showsInteractiveSideControls ? 1 : 0)
            .allowsHitTesting(showsInteractiveSideControls)

            Button { startQuickUninstall() } label: {
                sideToolIcon("shippingbox", tint: .blue, selected: maintenance.quickMode == .uninstall, size: 30)
            }
            .buttonStyle(.plain)
            .onHover { setSideToolHover(.uninstall, hovering: $0) }
            .overlay { sideHoverLabel(for: .uninstall) }
            .help("软件卸载")
            .opacity(showsInteractiveSideControls ? 1 : 0)
            .allowsHitTesting(showsInteractiveSideControls)
        }
        .frame(width: PetLayout.compactSideControlsWidth)
    }

    private func focusSideButton(size: CGFloat) -> some View {
        Button { showsFocusPopover.toggle() } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: hasActiveFocusCountdown
                                ? (focusTimer.state == .paused ? [.red.opacity(0.76), .orange.opacity(0.78)] : [.red, .orange])
                                : [.white.opacity(0.92), .red.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if hasActiveFocusCountdown {
                    Text(focusTimer.timeText)
                        .font(.system(size: max(8, size * 0.22), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                    Circle()
                        .trim(from: 0, to: max(focusTimer.progress, 0.03))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                } else {
                    Text("🍅")
                        .font(.system(size: size * 0.52))
                }
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 0.9))
            .shadow(color: .red.opacity(0.24), radius: 8, y: 3)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!store.interactionLocked)
        .onHover { setSideToolHover(.focus, hovering: $0) }
        .overlay { sideHoverLabel(for: .focus) }
        .help(hasActiveFocusCountdown ? "专注中：\(focusTimer.timeText)" : "打开番茄钟")
        .popover(isPresented: $showsFocusPopover, arrowEdge: sideControlsOnRight ? .trailing : .leading) {
            FocusTimerControlView(timer: focusTimer) { }
        }
    }

    private var showsTransientSideControls: Bool {
        isHovering || showsFocusPopover
    }

    private var showsInteractiveSideControls: Bool {
        showsTransientSideControls && !store.interactionLocked
    }

    private var hasActiveFocusCountdown: Bool {
        focusTimer.state == .running || focusTimer.state == .paused
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
                .help("空间清理：扫描可安全清理的缓存、日志和临时文件")
                .offset(x: sideControlsOnRight ? 7 : -7)

                Button {
                    startQuickUninstall()
                } label: {
                    sideToolIcon("shippingbox", tint: .blue, selected: maintenance.quickMode == .uninstall)
                }
                .buttonStyle(.plain)
                .onHover { setSideToolHover(.uninstall, hovering: $0) }
                .overlay { sideHoverLabel(for: .uninstall) }
                .help("软件卸载：查找应用及其可确认的用户级残留")
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
        Button("设置…") { appActions.open(.settings) }
        Divider()
        Button("打开废纸篓") { store.openTrash() }
        Button("清空废纸篓…") { store.confirmAndEmptyTrash() }
        Divider()
        Button("退出元圭与 VCC") { NSApp.terminate(nil) }
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
                updateAdaptiveControlSide(for: window)
            }
            .onEnded { _ in
                if let window = NSApp.windows.first(where: { $0 is PetPanel }) as? PetPanel {
                    window.isUserDragging = false
                    updateAdaptiveControlSide(for: window)
                    window.dragEndedAction?()
                }
                dragStartOrigin = nil
                dragStartMouseLocation = nil
            }
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
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
        group.notify(queue: .main) { store.recycle(urls) }
        return true
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
