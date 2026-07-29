import SwiftUI

struct DashboardMusicTransportControls: View {
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore

    init(music: MusicFeature) {
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
    }

    var body: some View {
        HStack(spacing: 8) {
            DashboardMusicTransportButton(
                title: "上一首",
                systemImage: "backward.fill",
                isProminent: false,
                action: music.previous
            )
            DashboardMusicTransportButton(
                title: playback.isPlaying ? "暂停" : "播放",
                systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                isProminent: true,
                action: music.playPause
            )
            DashboardMusicTransportButton(
                title: "下一首",
                systemImage: "forward.fill",
                isProminent: false,
                action: music.next
            )
        }
        .disabled(!music.canControl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("播放控制")
    }
}

private struct DashboardMusicTransportButton: View {
    let title: String
    let systemImage: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(
                    width: isProminent ? 26 : 22,
                    height: isProminent ? 26 : 22
                )
        }
        .dashboardSystemGlassButton(isProminent: isProminent)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}
