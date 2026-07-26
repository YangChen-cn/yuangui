import SwiftUI

struct PetDockPreviewView: View {
    let edge: PetDockEdge
    let isCommitReady: Bool

    var body: some View {
        Capsule()
            .fill(.white.opacity(isCommitReady ? 0.30 : 0.14))
            .overlay {
                Capsule()
                    .stroke(.white.opacity(isCommitReady ? 0.32 : 0.12), lineWidth: 1)
            }
            .shadow(color: .accentColor.opacity(isCommitReady ? 0.26 : 0.10), radius: isCommitReady ? 8 : 4)
            .opacity(edge == .left || edge == .right ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: isCommitReady)
            .accessibilityHidden(true)
    }
}
