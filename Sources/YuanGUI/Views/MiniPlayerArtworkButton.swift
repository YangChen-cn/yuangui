import SwiftUI

struct MiniPlayerArtworkButton: View {
    let track: MusicTrack?
    let action: () -> Void
    var size: CGFloat = 52

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                MusicArtworkView(track: track, size: size)

                MiniPlayerArtworkEdgeHint(
                    isActive: isHovering,
                    reduceMotion: reduceMotion
                )
                    .padding(3)

                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.blue.opacity(isHovering ? 0.96 : 0.74), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .scaleEffect(reduceMotion || !isHovering ? 0.88 : 1)
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .scaleEffect(reduceMotion || !isHovering ? 1 : 1.035)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18), value: isHovering)
        .help("打开完整播放器")
        .accessibilityLabel("打开完整播放器")
        .accessibilityHint("点击歌曲封面打开完整播放器")
    }
}

private struct MiniPlayerArtworkEdgeHint: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            HStack {
                edge(width: 2, height: 17)
                Spacer()
                edge(width: 2, height: 17)
            }
            VStack {
                edge(width: 17, height: 2)
                Spacer()
                edge(width: 17, height: 2)
            }
        }
        .foregroundStyle(.blue)
        .opacity(isActive ? 1 : 0)
        .scaleEffect(reduceMotion || isActive ? 1 : 0.72)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func edge(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(.blue)
            .frame(width: width, height: height)
            .shadow(color: .white.opacity(0.9), radius: 1)
    }
}
