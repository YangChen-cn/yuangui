import Foundation

struct DashboardQueuePresentation: Equatable {
    let tracks: [MusicTrack]
    let remainingCount: Int

    static func resolve(
        upcoming: [MusicTrack],
        currentTrackID: String?,
        limit: Int = DashboardDesign.queueLimit
    ) -> Self {
        let filtered = upcoming.filter { $0.id != currentTrackID }
        let visible = Array(filtered.prefix(max(limit, 0)))
        return Self(
            tracks: visible,
            remainingCount: max(filtered.count - visible.count, 0)
        )
    }
}
