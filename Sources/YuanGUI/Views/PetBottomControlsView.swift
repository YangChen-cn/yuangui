import SwiftUI

struct PetBottomControlsView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @Binding var isMiniPlayerPresented: Bool
    @Environment(\.appActions) private var appActions
    @State private var hoveredTip: String?

    init(
        store: PetStore,
        chat: ChatStore,
        music: MusicFeature,
        isMiniPlayerPresented: Binding<Bool>
    ) {
        self.store = store
        self.chat = chat
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        _isMiniPlayerPresented = isMiniPlayerPresented
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            controls

            if let hoveredTip {
                PetHoverLabel(text: hoveredTip)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(
            width: PetLayout.bottomToolbarPanelSize.width,
            height: PetLayout.bottomToolbarPanelSize.height,
            alignment: .bottom
        )
        .animation(.easeOut(duration: 0.14), value: hoveredTip)
        .onChange(of: store.interactionLocked) { _, locked in
            if locked { hoveredTip = nil }
        }
    }

    private var controls: some View {
        HStack(spacing: PetLayout.bottomToolbarSpacing) {
            Button { store.toggleSystemStatus() } label: {
                toolIcon(
                    store.shouldShowPetBubble
                        ? "gauge.with.dots.needle.67percent"
                        : "gauge.with.dots.needle.33percent",
                    tint: .pink,
                    selected: store.shouldShowPetBubble
                )
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? (store.shouldShowPetBubble ? "隐藏迷你监控" : "显示迷你监控") : nil) }
            .help(AppLocalizer.string(store.shouldShowPetBubble ? "隐藏桌宠迷你监控" : "显示 CPU、内存和电量迷你监控"))
            .accessibilityLabel(AppLocalizer.string(store.shouldShowPetBubble ? "隐藏迷你监控" : "显示迷你监控"))

            Button {
                appActions.open(.chat)
            } label: {
                toolIcon("bubble.left.and.bubble.right", tint: .pink, selected: chat.isPresented)
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? (chat.isPresented ? "收起 AI 对话" : "打开 AI 对话") : nil) }
            .help(AppLocalizer.string(chat.isPresented ? "收起 AI 输入框" : "和元圭、VCC 聊天，可粘贴图片或添加文件"))
            .accessibilityLabel(AppLocalizer.string(chat.isPresented ? "收起 AI 对话" : "打开 AI 对话"))

            Button { isMiniPlayerPresented.toggle() } label: {
                toolIcon("music.note", tint: .purple, selected: playback.isPlaying)
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? (playback.isPlaying ? "正在播放音乐" : "打开迷你播放器") : nil) }
            .help(AppLocalizer.string("YuanGUI 音乐播放器"))
            .accessibilityLabel(AppLocalizer.string(playback.isPlaying ? "正在播放音乐" : "打开迷你播放器"))
            .popover(isPresented: $isMiniPlayerPresented, arrowEdge: .bottom) {
                MiniMusicPlayerView(music: music)
            }

            Button {
                appActions.open(.quickDiary)
            } label: {
                toolIcon("square.and.pencil", tint: .pink)
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? "快速记录" : nil) }
            .help(AppLocalizer.string("快速记录这一刻"))
            .accessibilityLabel(AppLocalizer.string("快速记录"))

            Button { store.toggleInteractionLock() } label: {
                toolIcon(
                    "lock.open.fill",
                    tint: .orange,
                    selected: false
                )
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? "锁定并允许穿透" : nil) }
            .help(AppLocalizer.string("锁定桌宠：主体允许点击穿透，悬停仍可唤出解锁按钮"))
            .accessibilityLabel(AppLocalizer.string("锁定并允许穿透"))

        }
        .padding(PetLayout.bottomToolbarPanelPadding)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private func setTip(_ text: String?) {
        hoveredTip = text
    }

    private func toolIcon(_ systemName: String, tint: Color = .secondary, selected: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(selected ? tint : Color.primary.opacity(0.78))
            .frame(width: PetLayout.bottomToolbarButtonWidth, height: 28)
            .background(selected ? tint.opacity(0.16) : Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}
