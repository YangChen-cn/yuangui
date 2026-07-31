import SwiftUI

struct DiaryEntryList: View {
    @ObservedObject var store: DiaryFeature
    let onCreateNew: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var pendingDelete: DiaryEntry?
    @State private var pendingDeleteIDs = Set<UUID>()
    @State private var selectedEntryIDs = Set<UUID>()
    @State private var showBatchDeleteConfirmation = false
    @State private var isSelectionMode = false

    var body: some View {
        VStack(spacing: 0) {
            DiaryEntryListHeader(
                store: store,
                isSelectionMode: $isSelectionMode,
                selectedCount: selectedEntryIDs.count,
                allVisibleEntriesSelected: allVisibleEntriesSelected,
                toggleSelectAll: toggleSelectAll
            )
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
        .confirmationDialog(AppLocalizer.string("将这篇日记移到最近删除？"), item: $pendingDelete) { entry in
            Button(AppLocalizer.string("移到最近删除"), role: .destructive) { delete(entry) }
            Button(AppLocalizer.string("取消"), role: .cancel) {}
        }
        .confirmationDialog(
            AppLocalizer.format("diary.list.batchDeleteConfirmation", pendingDeleteIDs.count),
            isPresented: $showBatchDeleteConfirmation
        ) {
            Button(AppLocalizer.string("移到最近删除"), role: .destructive) { deleteSelected() }
            Button(AppLocalizer.string("取消"), role: .cancel) {}
        }
        .onChange(of: selectedEntryIDs) { _, ids in
            guard isSelectionMode else { return }
            synchronizeStoreSelection(ids)
        }
        .onChange(of: visibleEntryIDs) { _, ids in
            selectedEntryIDs.formIntersection(ids)
        }
        .onChange(of: store.selectedEntryID) { _, id in
            guard !isSelectionMode, let id else { return }
            selectedEntryIDs = [id]
        }
        .onChange(of: isSelectionMode) { _, enabled in
            selectedEntryIDs.removeAll()
            if enabled { pendingDeleteIDs.removeAll() }
        }
    }

    @ViewBuilder
    private var timelineList: some View {
        if isSelectionMode {
            List {
                ForEach(groupedEntries) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            selectionRow(entry)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .contextMenu {
                if !selectedEntryIDs.isEmpty {
                    Button(AppLocalizer.string(allEntriesFavorited(selectedEntryIDs) ? "取消收藏所选" : "收藏所选")) {
                        toggleFavorite(for: selectedEntryIDs)
                    }
                    Divider()
                    Button(AppLocalizer.string(selectedEntryIDs.count > 1 ? "删除所选…" : "删除…"), role: .destructive) {
                        pendingDeleteIDs = selectedEntryIDs
                        showBatchDeleteConfirmation = true
                    }
                }
            }
        } else {
            List(selection: $store.selectedEntryID) {
                ForEach(groupedEntries) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            DiaryEntryRow(store: store, entry: entry)
                                .tag(entry.id)
                                .contextMenu {
                                    Button(AppLocalizer.string(entry.isFavorite ? "取消收藏" : "收藏")) {
                                        store.toggleFavorite(id: entry.id)
                                    }
                                    Divider()
                                    Button(AppLocalizer.string("删除"), role: .destructive) { pendingDelete = entry }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func selectionRow(_ entry: DiaryEntry) -> some View {
        let isSelected = selectedEntryIDs.contains(entry.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.diaryAccent : .secondary)
                .font(.title3)
                .accessibilityHidden(true)
            DiaryEntryRow(store: store, entry: entry)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleEntrySelection(entry.id) }
        .listRowBackground(isSelected ? Color.diarySelection : Color.clear)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggleEntrySelection(entry.id) }
        .accessibilityLabel(entry.displayTitle.isEmpty ? AppLocalizer.string("未命名日记") : entry.displayTitle)
        .accessibilityValue(AppLocalizer.string(isSelected ? "已选择" : "未选择"))
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

    private var visibleEntryIDs: [UUID] {
        store.filteredEntries.map(\.id)
    }

    private var allVisibleEntriesSelected: Bool {
        !visibleEntryIDs.isEmpty && Set(visibleEntryIDs).isSubset(of: selectedEntryIDs)
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
            selectedEntryIDs.remove(entry.id)
            undoManager?.registerUndo(withTarget: store) { target in
                Task { await target.restoreDeleted(id: deleted.id) }
            }
            undoManager?.setActionName(AppLocalizer.string("恢复日记"))
        }
    }

    private func toggleSelectAll() {
        let visibleIDs = Set(visibleEntryIDs)
        if allVisibleEntriesSelected {
            selectedEntryIDs.subtract(visibleIDs)
        } else {
            selectedEntryIDs.formUnion(visibleIDs)
        }
    }

    private func toggleEntrySelection(_ id: UUID) {
        if selectedEntryIDs.contains(id) {
            selectedEntryIDs.remove(id)
        } else {
            selectedEntryIDs.insert(id)
        }
    }

    private func allEntriesFavorited(_ ids: Set<UUID>) -> Bool {
        !ids.isEmpty && ids.allSatisfy { id in
            store.entries.first(where: { $0.id == id })?.isFavorite == true
        }
    }

    private func toggleFavorite(for ids: Set<UUID>) {
        let shouldFavorite = !allEntriesFavorited(ids)
        for id in ids {
            guard let entry = store.entries.first(where: { $0.id == id }),
                  entry.isFavorite != shouldFavorite else { continue }
            store.toggleFavorite(id: id)
        }
    }

    private func synchronizeStoreSelection(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if let current = store.selectedEntryID, ids.contains(current) { return }
        store.selectedEntryID = ids.first
    }

    private func deleteSelected() {
        let ids = pendingDeleteIDs
        pendingDeleteIDs.removeAll()
        guard !ids.isEmpty else { return }
        Task {
            let deletedItems = await store.deleteEntries(ids: ids)
            guard !deletedItems.isEmpty else { return }
            let deletedIDs = Set(deletedItems.map(\.id))
            selectedEntryIDs.subtract(deletedIDs)
            undoManager?.registerUndo(withTarget: store) { target in
                Task { _ = await target.restoreDeleted(ids: deletedIDs) }
            }
            undoManager?.setActionName(AppLocalizer.string("恢复日记"))
        }
    }
}

private struct DiaryTimelineGroup: Identifiable {
    let day: Date
    let entries: [DiaryEntry]

    var id: Date { day }

    var title: String {
        if Calendar.current.isDateInToday(day) { return AppLocalizer.string("今天") }
        if Calendar.current.isDateInYesterday(day) { return AppLocalizer.string("昨天") }
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
