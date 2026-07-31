import AppKit
import SwiftUI

struct MusicArtworkView: View {
    let track: MusicTrack?
    var size: CGFloat = 54
    @State private var localArtwork: NSImage?

    var body: some View {
        Group {
            if let localArtwork {
                Image(nsImage: localArtwork).resizable().scaledToFill()
            } else if let url = displayCoverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(.primary.opacity(0.12), lineWidth: 0.7))
        .task(id: track?.localArtworkCacheKey) {
            localArtwork = nil
            guard let track, track.localArtworkCacheKey != nil,
                  let data = await LocalMusicArtworkRepository.shared.data(for: track) else { return }
            localArtwork = NSImage(data: data)
        }
    }

    private var displayCoverURL: URL? {
        guard let url = track?.coverURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return track?.coverURL
        }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        return components.url
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.pink.opacity(0.72), .purple.opacity(0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: track?.source.systemImage ?? "music.note")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct MusicTransportControls: View {
    let commands: any MusicPlaybackCommanding
    @ObservedObject private var playback: MusicPlaybackStore
    var compact = false
    var usesGlassButtons = false

    init(music: MusicFeature, compact: Bool = false, usesGlassButtons: Bool = false) {
        commands = music
        _playback = ObservedObject(wrappedValue: music.playback)
        self.compact = compact
        self.usesGlassButtons = usesGlassButtons
    }

    var body: some View {
        HStack(spacing: compact ? 15 : 22) {
            Button(action: commands.previous) { Image(systemName: "backward.fill") }
                .modifier(MusicTransportButtonModifier(usesGlass: usesGlassButtons))
                .help("上一首")
                .accessibilityLabel("上一首")
            Button(action: commands.playPause) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 15 : 20, weight: .bold))
                    .frame(width: compact ? 27 : 38, height: compact ? 27 : 38)
                    .background(
                        usesGlassButtons ? Color.clear : Color.primary.opacity(0.10),
                        in: Circle()
                    )
            }
            .modifier(MusicTransportButtonModifier(
                usesGlass: usesGlassButtons,
                isProminent: compact && usesGlassButtons && commands.canControl
            ))
            .help(AppLocalizer.string(playback.isPlaying ? "暂停" : "播放"))
            .accessibilityLabel(AppLocalizer.string(playback.isPlaying ? "暂停" : "播放"))
            Button(action: commands.next) { Image(systemName: "forward.fill") }
                .modifier(MusicTransportButtonModifier(usesGlass: usesGlassButtons))
                .help("下一首")
                .accessibilityLabel("下一首")
        }
        .disabled(!commands.canControl)
    }
}

private struct MusicTransportButtonModifier: ViewModifier {
    let usesGlass: Bool
    var isProminent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesGlass {
            if isProminent {
                content
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.blue, in: Circle())
            } else {
                content.yuanSystemGlassButton()
            }
        } else {
            content.buttonStyle(.plain)
        }
    }
}

struct MusicProgressView: View {
    let commands: any MusicPlaybackCommanding
    @ObservedObject private var progress: MusicPlaybackProgress
    @State private var previewPosition: TimeInterval = 0
    @State private var isSeeking = false

    init(music: MusicFeature) {
        commands = music
        _progress = ObservedObject(wrappedValue: music.playback.progress)
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isSeeking ? previewPosition : progress.position },
                    set: { newPosition in
                        previewPosition = newPosition
                        if !isSeeking { commands.seek(to: newPosition) }
                    }
                ),
                in: 0...max(progress.duration, 1),
                onEditingChanged: handleSeeking
            )
                .controlSize(.mini)
                .disabled(progress.duration <= 0)
                .help("拖动调整播放位置")
                .accessibilityLabel("播放进度")
            HStack {
                Text(formatTime(isSeeking ? previewPosition : progress.position))
                Spacer()
                Text(formatTime(progress.duration))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func handleSeeking(_ editing: Bool) {
        if editing {
            previewPosition = progress.position
            isSeeking = true
        } else if isSeeking {
            let target = previewPosition
            isSeeking = false
            commands.seek(to: target)
        }
    }
}

struct MusicVolumeControl: View {
    let commands: any MusicPlaybackCommanding
    @ObservedObject private var playback: MusicPlaybackStore
    var compact = false

    init(music: MusicFeature, compact: Bool = false) {
        commands = music
        _playback = ObservedObject(wrappedValue: music.playback)
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 9) {
            Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: compact ? 10 : 13))
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { playback.volume }, set: commands.setVolume), in: 0...1)
                .controlSize(compact ? .mini : .regular)
                .accessibilityLabel("音量")
            Text("\(Int((playback.volume * 100).rounded()))%")
                .font(.system(size: compact ? 9 : 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 28 : 34, alignment: .trailing)
        }
        .help("调整音量")
    }
}
