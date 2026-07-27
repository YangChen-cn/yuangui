import SwiftUI

struct DashboardMusicSourceMenu: View {
    let selection: MusicSource
    let onSelect: (MusicSource) -> Void

    var body: some View {
        Menu(selection.title, systemImage: selection.systemImage) {
            ForEach(MusicSource.allCases) { source in
                Button {
                    onSelect(source)
                } label: {
                    Label(
                        source == selection
                            ? AppLocalizer.format("music.source.currentFormat", source.title)
                            : source.title,
                        systemImage: source == selection ? "checkmark" : source.systemImage
                    )
                }
                .disabled(source == selection)
            }
        }
        .menuStyle(.borderlessButton)
        .font(.caption)
        .fixedSize()
        .help("切换音乐来源；选择 Apple Music 时自动连接")
        .accessibilityLabel("音乐来源")
        .accessibilityValue(selection.title)
    }
}
