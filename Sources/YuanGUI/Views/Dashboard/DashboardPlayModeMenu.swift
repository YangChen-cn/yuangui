import SwiftUI

struct DashboardPlayModeMenu: View {
    let selection: MusicPlayMode
    let onChange: (MusicPlayMode) -> Void

    var body: some View {
        Menu(selection.title, systemImage: selection.systemImage) {
            ForEach(MusicPlayMode.allCases) { mode in
                Button {
                    onChange(mode)
                } label: {
                    Label(mode.title, systemImage: mode == selection ? "checkmark" : mode.systemImage)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(AppLocalizer.format("music.playMode.currentFormat", selection.title))
        .accessibilityValue(selection.title)
    }
}
