import SwiftUI

struct PetDockPreviewView: View {
    @ObservedObject var presentation: PetDockPreviewPresentation

    var body: some View {
        Capsule()
            .fill(.white.opacity(presentation.isCommitReady ? 0.30 : 0.14))
            .overlay {
                Capsule()
                    .stroke(.white.opacity(presentation.isCommitReady ? 0.32 : 0.12), lineWidth: 1)
            }
            .shadow(
                color: .accentColor.opacity(presentation.isCommitReady ? 0.26 : 0.10),
                radius: presentation.isCommitReady ? 8 : 4
            )
            .opacity(presentation.edge == .left || presentation.edge == .right ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: presentation.isCommitReady)
            .accessibilityHidden(true)
    }
}
