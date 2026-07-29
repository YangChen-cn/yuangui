import Foundation

struct MusicLibraryQuery: Equatable, Sendable {
    enum SortField: String, CaseIterable, Identifiable, Sendable {
        case libraryOrder
        case title
        case artist
        case album
        case duration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .libraryOrder: AppLocalizer.string("music.library.sort.libraryOrder")
            case .title: AppLocalizer.string("music.library.sort.title")
            case .artist: AppLocalizer.string("music.library.sort.artist")
            case .album: AppLocalizer.string("music.library.sort.album")
            case .duration: AppLocalizer.string("music.library.sort.duration")
            }
        }
    }

    enum SortDirection: String, CaseIterable, Identifiable, Sendable {
        case ascending
        case descending

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ascending: AppLocalizer.string("music.library.sort.ascending")
            case .descending: AppLocalizer.string("music.library.sort.descending")
            }
        }

        var systemImage: String {
            switch self {
            case .ascending: "arrow.up"
            case .descending: "arrow.down"
            }
        }
    }

    var searchText = ""
    var sortField: SortField = .libraryOrder
    var sortDirection: SortDirection = .ascending

    func apply(to tracks: [MusicTrack]) -> [MusicTrack] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? tracks : tracks.filter { track in
            [track.title, track.artist, track.album, track.local?.originalFilename]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
        guard sortField != .libraryOrder else { return filtered }

        return filtered.enumerated().sorted { lhs, rhs in
            let comparison = compare(lhs.element, rhs.element)
            if comparison == .orderedSame { return lhs.offset < rhs.offset }
            return sortDirection == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }.map(\.element)
    }

    private func compare(_ lhs: MusicTrack, _ rhs: MusicTrack) -> ComparisonResult {
        switch sortField {
        case .libraryOrder:
            .orderedSame
        case .title:
            lhs.title.localizedStandardCompare(rhs.title)
        case .artist:
            lhs.artist.localizedStandardCompare(rhs.artist)
        case .album:
            (lhs.album ?? "").localizedStandardCompare(rhs.album ?? "")
        case .duration:
            if lhs.duration == rhs.duration {
                .orderedSame
            } else {
                lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending
            }
        }
    }
}
