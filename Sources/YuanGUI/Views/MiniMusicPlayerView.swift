import SwiftUI

struct MiniMusicPlayerView: View {
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore
    @Environment(\.appActions) private var appActions

    init(music: MusicFeature) {
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MusicArtworkView(track: playback.currentTrack, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.currentTrack?.title ?? AppLocalizer.string("暂无播放内容"))
                        .font(.headline)
                        .lineLimit(1)
                    Text(playback.currentTrack?.artist ?? playback.playbackSource.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Label(playback.playbackSource.title, systemImage: playback.playbackSource.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            MusicProgressView(music: music)
            HStack {
                MiniPlayerToggleButton(
                    systemImage: lyricsPresentation.isVisible ? "quote.bubble.fill" : "quote.bubble",
                    isSelected: lyricsPresentation.isVisible,
                    selectedTitle: "隐藏桌面歌词",
                    unselectedTitle: "显示桌面歌词"
                ) {
                    music.toggleLyricsVisible()
                }
                MiniPlayerToggleButton(
                    systemImage: lyricsPresentation.isPanelLocked ? "lock.fill" : "lock.open",
                    isSelected: lyricsPresentation.isPanelLocked,
                    selectedTitle: "解锁桌面歌词",
                    unselectedTitle: "锁定桌面歌词"
                ) {
                    music.setLyricsPanelLocked(!lyricsPresentation.isPanelLocked)
                }
                Spacer()
                MusicTransportControls(music: music, compact: true, usesGlassButtons: true)
                Spacer()
                Button { appActions.open(.music) } label: { Image(systemName: "list.bullet") }
                    .yuanSystemGlassButton()
                    .controlSize(.small)
                    .help("打开完整播放器")
                    .accessibilityLabel("打开完整播放器")
            }
        }
        .padding(12)
        .frame(width: 300)
        .yuanLiquidGlassSurface(.regular, cornerRadius: 22)
        .padding(6)
        .presentationBackground(.clear)
    }
}

private struct MiniPlayerToggleButton: View {
    let systemImage: String
    let isSelected: Bool
    let selectedTitle: String
    let unselectedTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(width: 34, height: 28)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .yuanSystemGlassButton(isProminent: isSelected)
        .controlSize(.small)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.72) : Color.clear,
                    lineWidth: 1
                )
        }
        .help(AppLocalizer.string(isSelected ? selectedTitle : unselectedTitle))
        .accessibilityLabel(AppLocalizer.string(isSelected ? selectedTitle : unselectedTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
