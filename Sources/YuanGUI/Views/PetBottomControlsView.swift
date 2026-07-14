import SwiftUI

struct PetBottomControlsView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore

    var body: some View {
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
            .help(store.shouldShowPetBubble ? "隐藏桌宠迷你监控" : "显示 CPU、内存和电量迷你监控")

            Button {
                if store.interactionLocked { store.setInteractionLocked(false) }
                store.showChat()
            } label: {
                toolIcon("bubble.left.and.bubble.right", tint: .pink, selected: chat.isPresented)
            }
            .buttonStyle(.plain)
            .help(chat.isPresented ? "收起 AI 输入框" : "和元圭、VCC 聊天，可粘贴图片或添加文件")

            Button { store.toggleInteractionLock() } label: {
                toolIcon(
                    store.interactionLocked ? "lock.fill" : "lock.open.fill",
                    tint: .orange,
                    selected: store.interactionLocked
                )
            }
            .buttonStyle(.plain)
            .help(store.interactionLocked ? "解锁桌宠，恢复点击和拖动" : "锁定桌宠：主体允许点击穿透，悬停仍可唤出工具栏")

            Menu {
                Button("缩小") { store.adjustPetScale(by: -0.1) }
                Button("恢复默认大小（85%）") { store.setPetScale(PetLayout.defaultScale) }
                Button("放大") { store.adjustPetScale(by: 0.1) }
            } label: {
                toolIcon("arrow.up.left.and.arrow.down.right")
            }
            .menuStyle(.borderlessButton)
            .frame(width: PetLayout.bottomToolbarButtonWidth)
            .help("调整桌宠显示大小")
        }
        .padding(PetLayout.bottomToolbarPanelPadding)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
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
