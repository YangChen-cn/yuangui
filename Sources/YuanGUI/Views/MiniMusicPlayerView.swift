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
                Button { music.toggleLyricsVisible() } label: {
                    Image(systemName: lyricsPresentation.isVisible ? "quote.bubble.fill" : "quote.bubble")
                }
                .yuanSystemGlassButton(isProminent: lyricsPresentation.isVisible)
                .controlSize(.small)
                .help(AppLocalizer.string(
                    lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词"
                ))
                .accessibilityLabel(AppLocalizer.string(
                    lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词"
                ))
                Button { music.setLyricsPanelLocked(!lyricsPresentation.isPanelLocked) } label: {
                    Image(systemName: lyricsPresentation.isPanelLocked ? "lock.fill" : "lock.open")
                }
                .yuanSystemGlassButton(isProminent: lyricsPresentation.isPanelLocked)
                .controlSize(.small)
                .help(AppLocalizer.string(
                    lyricsPresentation.isPanelLocked ? "解锁桌面歌词" : "锁定桌面歌词"
                ))
                .accessibilityLabel(AppLocalizer.string(
                    lyricsPresentation.isPanelLocked ? "解锁桌面歌词" : "锁定桌面歌词"
                ))
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
