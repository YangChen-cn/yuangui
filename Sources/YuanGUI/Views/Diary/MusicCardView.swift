import SwiftUI

/// 音乐快照卡片
struct MusicCardView: View {
    let music: DiaryMusicSnapshot?

    var body: some View {
        if let music, !music.title.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                Text(music.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Text("—")
                    .foregroundStyle(.secondary)
                Text(music.artist)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.purple.opacity(0.08), in: Capsule())
        }
    }
}
