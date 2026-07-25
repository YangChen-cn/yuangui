import SwiftUI

struct DashboardQueueRow: View {
    let track: MusicTrack
    let isPlaying: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                MusicArtworkView(track: track, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(DashboardMusicFormatting.time(track.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : (isHovering ? "play.fill" : "chevron.right"))
                    .font(.caption)
                    .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                    .frame(width: 14)
            }
            .padding(.horizontal, 6)
            .frame(height: DashboardDesign.rowHeight)
            .background(
                Color.primary.opacity(isHovering ? 0.065 : 0),
                in: .rect(cornerRadius: DashboardDesign.controlRadius)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(track.title)，\(track.artist)，\(DashboardMusicFormatting.time(track.duration))")
        .accessibilityHint("立即播放")
    }
}
