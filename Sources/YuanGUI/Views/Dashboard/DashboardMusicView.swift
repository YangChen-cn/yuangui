import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                    if track.source != .appleMusic {
                        Button {
                            music.toggleFavorite(track)
                        } label: {
                            Image(systemName: music.isFavorite(track) ? "heart.fill" : "heart")
                                .frame(width: 28, height: 28)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(music.isFavorite(track) ? Color.pink : Color.secondary)
                        .help(AppLocalizer.string(music.isFavorite(track) ? "取消收藏当前歌曲" : "收藏当前歌曲"))
                        .accessibilityLabel(AppLocalizer.string(music.isFavorite(track) ? "取消收藏" : "收藏"))
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
        .accessibilityLabel(AppLocalizer.format(
            "music.accessibility.nowPlaying",
            track.title,
            track.artist,
            track.source.title
        ))
    }

    @ViewBuilder
    private var queueSection: some View {
        if music.playback.source != .appleMusic {
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
                title: music.playback.source == .local ? "music.local.empty.title" : "暂无播放内容",
                systemImage: "music.note",
                description: emptyDescription
            )
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    emptyStateActions
                }
                VStack(spacing: 8) {
                    emptyStateActions
                }
            }
            .controlSize(.small)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyDescription: String {
        switch music.playback.source {
        case .appleMusic: AppLocalizer.string("连接 Music App 后可在这里快速控制。")
        case .local:
            AppLocalizer.string("music.local.empty.description")
                + "\n"
                + AppLocalizer.string("music.local.empty.privacy")
        case .bilibili: AppLocalizer.string("请在完整播放器中导入哔哩哔哩歌曲。")
        }
    }

    @ViewBuilder
    private var emptyStateActions: some View {
        ForEach(DashboardMusicEmptyAction.actions(for: music.playback.source)) { action in
            if let systemImage = action.systemImage {
                Button(action.title, systemImage: systemImage) {
                    performEmptyAction(action)
                }
            } else {
                Button(action.title) {
                    performEmptyAction(action)
                }
            }
        }
    }

    private func performEmptyAction(_ action: DashboardMusicEmptyAction) {
        switch action {
        case .connectAppleMusic:
            music.connectAppleMusic()
        case .importLocalMusic:
            importLocalMusic()
        case .openFullPlayer:
            openFullPlayer()
        }
    }

    private func importLocalMusic() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = LocalMusicImportService.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        if panel.runModal() == .OK { music.importLocalMusic(panel.urls) }
    }

    private func openFullPlayer() {
        dismiss()
        appActions.open(.music)
    }

    private func switchSource(_ source: MusicSource) {
        switch DashboardMusicSourceAction.resolve(source) {
        case .connectAppleMusic:
            music.connectAppleMusic()
        case .selectLocal:
            music.setSource(.local)
        case .selectBilibili:
            music.setSource(.bilibili)
        }
    }
}
