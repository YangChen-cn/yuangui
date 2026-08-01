import SwiftUI

struct PetBottomControlLayer: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    let music: MusicFeature
    @Binding var isMiniPlayerPresented: Bool
    let miniPlayerHandoff: MiniPlayerPopoverHandoff

    var body: some View {
        PetBottomControlsView(
            store: store,
            chat: chat,
            music: music,
            isMiniPlayerPresented: $isMiniPlayerPresented,
            miniPlayerHandoff: miniPlayerHandoff
        )
    }
}
