import SwiftUI

struct PetEdgePeekView: View {
    @ObservedObject var store: PetStore
    let edge: PetDockEdge
    let hoveringChanged: ((Bool) -> Void)?
    let expand: () -> Void
    @Environment(\.appActions) private var appActions

    init(
        store: PetStore,
        edge: PetDockEdge,
        hoveringChanged: ((Bool) -> Void)? = nil,
        expand: @escaping () -> Void
    ) {
        self.store = store
        self.edge = edge
        self.hoveringChanged = hoveringChanged
        self.expand = expand
    }

    var body: some View {
        Button(action: expand) {
            Group {
                if let image = SpriteLoader.edgePeekImage(mode: store.mode, edge: edge)
                    ?? SpriteLoader.image(mode: store.mode, action: store.currentAction) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(x: edge == .right ? -1 : 1, y: 1)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.pink)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: PetLayout.edgePeekSize.width, height: PetLayout.edgePeekSize.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hoveringChanged?($0) }
        .help("悬停探出桌宠，点击叫回")
        .accessibilityLabel("叫回桌宠")
        .frame(width: PetLayout.edgePeekSize.width, height: PetLayout.edgePeekSize.height)
        .contextMenu { dockedContextMenu }
    }

    @ViewBuilder
    private var dockedContextMenu: some View {
        Button("展开桌宠") { expand() }
        Button(store.showsSystemStatus ? "隐藏迷你监控" : "显示迷你监控") {
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
        Button("设置…") { appActions.open(.settings(.pet)) }
    }
}
