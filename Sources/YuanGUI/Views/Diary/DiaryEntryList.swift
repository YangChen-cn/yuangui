import SwiftUI

struct DiaryEntryList: View {
    @ObservedObject var store: DiaryFeature
    let onCreateNew: () -> Void
    @Environment(\.undoManager) private var undoManager
    @FocusState private var searchIsFocused: Bool
    @State private var pendingDelete: DiaryEntry?

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            if store.filteredEntries.isEmpty {
                DiaryEmptyState(
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: "book.closed",
                    actionTitle: "记录这一刻",
                    action: onCreateNew
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                timelineList
            }
        }
        .confirmationDialog("将这篇日记移到最近删除？", item: $pendingDelete) { entry in
            Button("移到最近删除", role: .destructive) { delete(entry) }
            Button("取消", role: .cancel) {}
        }
        .background {
            Button("") { searchIsFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索日记", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.diarySecondarySurface, in: RoundedRectangle(cornerRadius: DiaryDesign.smallCornerRadius))

            HStack {
                Text(listTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.filteredEntries.count) 篇")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var timelineList: some View {
        List(selection: $store.selectedEntryID) {
            ForEach(groupedEntries) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        DiaryEntryRow(store: store, entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button(entry.isFavorite ? "取消收藏" : "收藏") {
                                    store.toggleFavorite(id: entry.id)
                                }
                                Divider()
                                Button("删除…", role: .destructive) { pendingDelete = entry }
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var groupedEntries: [DiaryTimelineGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: store.filteredEntries) {
            calendar.startOfDay(for: $0.occurredAt)
        }
        return groups.keys.sorted(by: >).map {
            DiaryTimelineGroup(day: $0, entries: groups[$0] ?? [])
        }
    }

    private var listTitle: String {
        if !store.searchText.isEmpty { return "搜索结果" }
        if store.filter.favoritesOnly { return "收藏" }
        if let tag = store.filter.tag { return "#\(tag)" }
        if let day = store.filter.day { return day.formatted(.dateTime.month().day()) }
        if let month = store.filter.month { return month.formatted(.dateTime.year().month(.wide)) }
        return "时间线"
    }

    private var emptyTitle: String {
        store.searchText.isEmpty ? "还没有写下今天的故事" : "没有找到相关日记"
    }

    private var emptyMessage: String {
        store.searchText.isEmpty ? "记录一件刚刚发生的小事吧。" : "试试更短的关键词，或清除当前筛选。"
    }

    private func delete(_ entry: DiaryEntry) {
        Task {
            guard let deleted = await store.deleteEntry(id: entry.id) else { return }
            undoManager?.registerUndo(withTarget: store) { target in
                Task { await target.restoreDeleted(id: deleted.id) }
            }
            undoManager?.setActionName("恢复日记")
        }
    }
}

private struct DiaryTimelineGroup: Identifiable {
    let day: Date
    let entries: [DiaryEntry]

    var id: Date { day }

    var title: String {
        if Calendar.current.isDateInToday(day) { return "今天" }
        if Calendar.current.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day().weekday(.wide))
    }
}

private extension View {
    func confirmationDialog<Item>(
        _ title: String,
        item: Binding<Item?>,
        @ViewBuilder actions: @escaping (Item) -> some View
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            )
        ) {
            if let value = item.wrappedValue { actions(value) }
        }
    }
}
