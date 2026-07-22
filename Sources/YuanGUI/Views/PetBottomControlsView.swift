import SwiftUI

struct PetBottomControlsView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @ObservedObject var music: MusicStore
    @State private var hoveredTip: String?

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
            .help(store.shouldShowPetBubble ? "隐藏桌宠迷你监控" : "显示 CPU、内存和电量迷你监控")
            .disabled(store.interactionLocked)
            .opacity(store.interactionLocked ? 0.38 : 1)

            Button {
                store.showChat()
            } label: {
                toolIcon("bubble.left.and.bubble.right", tint: .pink, selected: chat.isPresented)
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? (chat.isPresented ? "收起 AI 对话" : "打开 AI 对话") : nil) }
            .help(chat.isPresented ? "收起 AI 输入框" : "和元圭、VCC 聊天，可粘贴图片或添加文件")
            .disabled(store.interactionLocked)
            .opacity(store.interactionLocked ? 0.38 : 1)

            Button { music.isMiniPlayerPresented.toggle() } label: {
                toolIcon("music.note", tint: .purple, selected: music.isPlaying)
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? (music.isPlaying ? "正在播放音乐" : "打开迷你播放器") : nil) }
            .help("YuanGUI 音乐播放器")
            .popover(isPresented: $music.isMiniPlayerPresented, arrowEdge: .bottom) {
                MiniMusicPlayerView(music: music)
            }
            .disabled(store.interactionLocked)
            .opacity(store.interactionLocked ? 0.38 : 1)

            Button {
                NotificationCenter.default.post(name: .startYuanGUIRegionScreenshot, object: nil)
            } label: {
                toolIcon("scissors", tint: .blue)
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? "区域截图" : nil) }
            .help("区域截图并编辑")
            .disabled(store.interactionLocked)
            .opacity(store.interactionLocked ? 0.38 : 1)

            Button { store.toggleInteractionLock() } label: {
                toolIcon(
                    store.interactionLocked ? "lock.fill" : "lock.open.fill",
                    tint: .orange,
                    selected: store.interactionLocked
                )
            }
            .buttonStyle(.plain)
            .onHover { setTip($0 ? (store.interactionLocked ? "解锁桌宠" : "锁定并允许穿透") : nil) }
            .help(store.interactionLocked ? "解锁桌宠，恢复点击和拖动" : "锁定桌宠：主体允许点击穿透，悬停仍可唤出工具栏")

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
