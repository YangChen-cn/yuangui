import SwiftUI

struct MusicLibraryFilterBar: View {
    @Binding var searchText: String
    @Binding var sortField: MusicLibraryQuery.SortField
    @Binding var sortDirection: MusicLibraryQuery.SortDirection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                searchField
                sortMenu
                directionMenu
            }
            VStack(alignment: .leading, spacing: 8) {
                searchField
                HStack(spacing: 8) {
                    sortMenu
                    directionMenu
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        TextField(
            AppLocalizer.string("music.library.search.placeholder"),
            text: $searchText
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(AppLocalizer.string("music.library.search.accessibility"))
    }

    private var sortMenu: some View {
        Menu {
            Picker(AppLocalizer.string("music.library.sort.label"), selection: $sortField) {
                ForEach(MusicLibraryQuery.SortField.allCases) { field in
                    Text(field.title).tag(field)
                }
            }
        } label: {
            Label(sortField.title, systemImage: "arrow.up.arrow.down")
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityLabel(AppLocalizer.string("music.library.sort.label"))
    }

    private var directionMenu: some View {
        Menu {
            Picker(AppLocalizer.string("music.library.sort.direction"), selection: $sortDirection) {
                ForEach(MusicLibraryQuery.SortDirection.allCases) { direction in
                    Label(direction.title, systemImage: direction.systemImage).tag(direction)
                }
            }
        } label: {
            Label(sortDirection.title, systemImage: sortDirection.systemImage)
                .labelStyle(.iconOnly)
        }
        .disabled(sortField == .libraryOrder)
        .accessibilityLabel(
            AppLocalizer.format("music.library.sort.direction.current", sortDirection.title)
        )
    }
}
