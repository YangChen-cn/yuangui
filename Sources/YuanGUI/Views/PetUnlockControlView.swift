import SwiftUI

struct PetUnlockControlView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        Button {
            store.setInteractionLocked(false)
        } label: {
            Image(systemName: "lock.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.orange.opacity(0.28), lineWidth: 0.8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("解锁桌宠，恢复点击和拖动")
        .accessibilityLabel("解锁桌宠")
        .frame(
            width: PetLayout.lockedControlPanelSize.width,
            height: PetLayout.lockedControlPanelSize.height
        )
    }
}
