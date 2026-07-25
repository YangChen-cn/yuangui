import SwiftUI

struct DashboardUpNextSection: View {
    let tracks: [MusicTrack]
    let remainingCount: Int
    let playMode: MusicPlayMode
    let onPlay: (MusicTrack) -> Void
    let onChangePlayMode: (MusicPlayMode) -> Void
    let onOpenFullQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("接下来播放")
                    .font(.caption)
                    .bold()
                Spacer()
                DashboardPlayModeMenu(selection: playMode, onChange: onChangePlayMode)
            }
            if tracks.isEmpty {
                Text("接下来没有歌曲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            DashboardQueueRow(track: track, isPlaying: false) {
                                onPlay(track)
                            }
                        }
                    }
                }
                .frame(maxHeight: 128)
                .scrollIndicators(.hidden)
            }
            HStack {
                if remainingCount > 0 {
                    Text("还有 \(remainingCount) 首")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开完整队列", systemImage: "list.bullet", action: onOpenFullQueue)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("接下来播放")
    }
}
