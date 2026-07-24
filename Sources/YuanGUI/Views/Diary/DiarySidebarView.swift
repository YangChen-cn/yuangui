import SwiftUI

struct DiarySidebarView: View {
    @ObservedObject var store: DiaryFeature

    var body: some View {
        List {
            Section {
                HStack {
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Button(monthTitle) { store.selectMonth(displayedMonth) }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
            }

            Section {
                sidebarButton("全部日记", icon: "book.fill", active: store.filter == DiaryFilter()) {
                    store.clearFilters()
                    store.viewMode = .timeline
                }
                sidebarButton("收藏", icon: "star.fill", active: store.filter.favoritesOnly) {
                    store.filter = DiaryFilter(favoritesOnly: true)
                    store.viewMode = .timeline
                }
                sidebarButton("最近删除", icon: "trash", active: store.viewMode == .recentlyDeleted) {
                    store.viewMode = .recentlyDeleted
                }
            }

            if !store.allTags.isEmpty {
                Section("标签") {
                    ForEach(store.allTags, id: \.self) { tag in
                        sidebarButton("#\(tag)", icon: "tag", active: store.filter.tag?.caseInsensitiveCompare(tag) == .orderedSame) {
                            store.filter = DiaryFilter(tag: tag)
                            store.viewMode = .timeline
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("\(store.entries.count) 条日记")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sidebarButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(active ? AnyShapeStyle(.pink) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var displayedMonth: Date { store.filter.month ?? Date() }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private func changeMonth(_ offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        store.selectMonth(month)
    }
}
