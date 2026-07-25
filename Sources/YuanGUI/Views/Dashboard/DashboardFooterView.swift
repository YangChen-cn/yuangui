import AppKit
import SwiftUI

struct DashboardFooterView: View {
    @ObservedObject var store: PetStore
    let togglePet: () -> Void
    let showPet: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            DashboardToggleButton(
                title: "桌宠显示",
                systemImage: store.isPetPresented ? "pawprint.fill" : "pawprint",
                isOn: store.isPetPresented,
                action: togglePet
            )
            DashboardToggleButton(
                title: "迷你状态",
                systemImage: store.shouldShowPetBubble ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.0percent",
                isOn: store.shouldShowPetBubble,
                action: toggleMiniStatus
            )
            DashboardToggleButton(
                title: "桌面图标",
                systemImage: store.desktopIconsVisible ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2",
                isOn: store.desktopIconsVisible,
                action: store.toggleDesktopIcons
            )
            DashboardToggleButton(
                title: "锁定桌宠",
                systemImage: store.interactionLocked ? "lock.fill" : "lock.open",
                isOn: store.interactionLocked,
                action: toggleLock
            )
            Spacer(minLength: 4)
            Menu("更多", systemImage: "ellipsis.circle") {
                Button("打开废纸篓", systemImage: "trash") {
                    store.openTrash()
                }
                Button("清空废纸篓…", systemImage: "trash.slash") {
                    store.confirmAndEmptyTrash()
                }
                Divider()
                Button("退出元圭与 VCC", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("更多操作")
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("常用状态控制")
    }

    private func toggleMiniStatus() {
        store.toggleSystemStatus()
        showPet()
    }

    private func toggleLock() {
        store.toggleInteractionLock()
        showPet()
    }
}
