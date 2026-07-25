import SwiftUI

struct DashboardMusicView: View {
    @ObservedMusicFeature var music: MusicFeature
    @ObservedObject var externalAudioInterruption: ExternalAudioInterruptionController
    let dismiss: () -> Void

    @Environment(\.appActions) private var appActions

    var body: some View {
        VStack(spacing: 9) {
            if let track = music.playback.currentTrack {
                nowPlaying(track)
                queueSection
                settingsRow
            } else {
                emptyState
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("音乐")
    }

    private func nowPlaying(_ track: MusicTrack) -> some View {
        DashboardSectionSurface(prominence: .hero) {
            VStack(spacing: 7) {
                HStack(spacing: 12) {
                    MusicArtworkView(track: track, size: 66)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        DashboardMusicSourceMenu(
                            selection: music.playback.source,
                            onSelect: switchSource
                        )
                    }
                    Spacer(minLength: 4)
                    if track.source == .bilibili {
                        Button {
                            music.toggleFavorite(track)
                        } label: {
                            Image(systemName: music.isFavorite(track) ? "heart.fill" : "heart")
                                .frame(width: 28, height: 28)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(music.isFavorite(track) ? Color.pink : Color.secondary)
                        .help(music.isFavorite(track) ? "取消收藏当前歌曲" : "收藏当前歌曲")
                        .accessibilityLabel(music.isFavorite(track) ? "取消收藏" : "收藏")
                    }
                }
                MusicProgressView(music: music)
                HStack(spacing: 14) {
                    Spacer()
                    DashboardMusicTransportControls(music: music)
                    MusicVolumeControl(music: music, compact: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在播放 \(track.title)，\(track.artist)，来源 \(track.source.title)")
    }

    @ViewBuilder
    private var queueSection: some View {
        if music.playback.source == .bilibili {
            let presentation = DashboardQueuePresentation.resolve(
                upcoming: music.upcomingTracks,
                currentTrackID: music.playback.currentTrack?.id
            )
            DashboardUpNextSection(
                tracks: presentation.tracks,
                remainingCount: presentation.remainingCount,
                playMode: music.playback.playMode,
                onPlay: { music.play($0) },
                onChangePlayMode: music.setPlayMode,
                onOpenFullQueue: openFullPlayer
            )
        } else {
            VStack(spacing: 5) {
                Divider()
                HStack(spacing: 8) {
                    Label("播放队列由 Music App 管理", systemImage: "music.note.list")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("打开 Music 队列", action: music.openAppleMusic)
                        .buttonStyle(.plain)
                        .font(.caption)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Apple Music 播放队列由 Music App 管理")
        }
    }

    private var settingsRow: some View {
        HStack(spacing: 12) {
            Toggle("自动暂停", isOn: Binding(
                get: { externalAudioInterruption.isEnabled },
                set: externalAudioInterruption.setEnabled
            ))
            .help("其他应用持续播放声音时自动暂停音乐")
            .accessibilityLabel("外部声音自动暂停")
            Toggle("桌面歌词", isOn: Binding(
                get: { music.lyricsPresentation.isVisible },
                set: { _ in music.toggleLyricsVisible() }
            ))
            .help("显示或隐藏桌面歌词")
            Spacer()
            Button("打开完整播放器", systemImage: "arrow.up.right.square", action: openFullPlayer)
                .buttonStyle(.plain)
                .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            HStack {
                Text("音乐")
                    .font(.caption)
                    .bold()
                Spacer()
                DashboardMusicSourceMenu(
                    selection: music.playback.source,
                    onSelect: switchSource
                )
            }
            DashboardEmptyState(
                title: "暂无播放内容",
                systemImage: "music.note",
                description: music.playback.source == .appleMusic
                    ? "连接 Music App 后可在这里快速控制。"
                    : "请在完整播放器中导入哔哩哔哩歌曲。"
            )
            Button(music.playback.source == .appleMusic ? "连接 Apple Music" : "打开完整播放器") {
                if music.playback.source == .appleMusic {
                    music.connectAppleMusic()
                } else {
                    openFullPlayer()
                }
            }
            .controlSize(.small)
        }
        .frame(maxHeight: .infinity)
    }

    private func openFullPlayer() {
        dismiss()
        appActions.open(.music)
    }

    private func switchSource(_ source: MusicSource) {
        switch DashboardMusicSourceAction.resolve(source) {
        case .connectAppleMusic:
            music.connectAppleMusic()
        case .selectBilibili:
            music.setSource(.bilibili)
        }
    }
}
