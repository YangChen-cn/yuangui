import SwiftUI

struct PetEdgePeekView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var monitor: SystemMonitor
    let edge: PetDockEdge
    let expand: () -> Void
    @Environment(\.appActions) private var appActions
    @State private var hovering = false

    init(store: PetStore, edge: PetDockEdge, expand: @escaping () -> Void) {
        self.store = store
        self.edge = edge
        self.expand = expand
        _monitor = ObservedObject(wrappedValue: store.monitor)
    }

    var body: some View {
        HStack(spacing: 5) {
            if store.shouldShowPetBubble && edge != .left {
                miniStatus
            }
            headButton
            if store.shouldShowPetBubble && edge == .left {
                miniStatus
            }
        }
        .frame(
            width: PetLayout.edgePeekPanelSize(showsMiniStatus: store.shouldShowPetBubble).width,
            height: PetLayout.edgePeekPanelSize(showsMiniStatus: store.shouldShowPetBubble).height
        )
        .contextMenu { dockedContextMenu }
    }

    private var headButton: some View {
        Button(action: expand) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.22), .purple.opacity(0.12), .cyan.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let image = SpriteLoader.image(mode: store.mode, action: store.currentAction) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: PetLayout.edgePeekSpriteSize, height: PetLayout.edgePeekSpriteSize)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.pink)
                }
            }
            .frame(width: PetLayout.edgePeekButtonDiameter, height: PetLayout.edgePeekButtonDiameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.22), radius: hovering ? 13 : 8, y: 4)
            .scaleEffect(hovering ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                hovering = value
            }
        }
        .help("点击叫回元圭与 VCC")
        .accessibilityLabel("叫回桌宠")
        .frame(width: 76, height: 76)
    }

    private var miniStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            miniMetric("cpu", value: percent(monitor.snapshot.cpu?.total), color: .pink)
            miniMetric("memorychip", value: percent(monitor.snapshot.memory?.fractionUsed), color: .purple)
            miniMetric(
                monitor.snapshot.battery?.isCharging == true ? "bolt.fill" : "battery.75percent",
                value: percent(monitor.snapshot.battery?.chargeFraction),
                color: .mint
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 111, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.55), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.13), radius: 8, y: 3)
    }

    private func miniMetric(_ icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 13)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    @ViewBuilder
    private var dockedContextMenu: some View {
        Button("展开桌宠") { expand() }
        Button(store.shouldShowPetBubble ? "隐藏迷你监控" : "显示迷你监控") {
            store.toggleSystemStatus()
        }
        Button("打开完整监控") { appActions.open(.statusDashboard) }
        Button("和元圭、VCC 聊天…") { appActions.open(.chat) }
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
        }
        Toggle("智能状态动作", isOn: Binding(
            get: { store.smartReactionsEnabled },
            set: { store.setSmartReactionsEnabled($0) }
        ))
        Button("设置…") { appActions.open(.settings) }
    }
}
