import SwiftUI

struct DiaryRecentlyDeletedView: View {
    @ObservedObject var store: DiaryFeature
    @State private var pendingPermanentDeleteIDs = Set<UUID>()
    @State private var selectedItemIDs = Set<UUID>()
    @State private var showPermanentDeleteConfirmation = false
    @State private var isSelectionMode = false

    var body: some View {
        if store.recentlyDeletedItems.isEmpty {
            DiaryEmptyState(
                title: "最近删除为空",
                message: "移除的日记会在这里保留 30 天。",
                systemImage: "trash"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                        Text(AppLocalizer.string("最近删除"))
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if isSelectionMode {
                        Button {
                            toggleSelectAll()
                        } label: {
                            Image(systemName: allItemsSelected ? "minus.square" : "checkmark.square")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 26, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(AppLocalizer.string(allItemsSelected ? "取消选择所有最近删除" : "选择所有最近删除"))
                        .accessibilityLabel(AppLocalizer.string(allItemsSelected ? "反全选" : "全选"))
                        if !selectedItemIDs.isEmpty {
                            Text(AppLocalizer.format("diary.list.selectedCount", selectedItemIDs.count))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Button(AppLocalizer.string("恢复"), systemImage: "arrow.uturn.backward") {
                                restore(selectedItemIDs)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            Button(AppLocalizer.string("删除"), systemImage: "trash", role: .destructive) {
                                pendingPermanentDeleteIDs = selectedItemIDs
                                showPermanentDeleteConfirmation = true
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                        Button(AppLocalizer.string("完成")) {
                            isSelectionMode = false
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    } else {
                        Button(AppLocalizer.string("选择"), systemImage: "checklist") {
                            isSelectionMode = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(AppLocalizer.string("选择多篇最近删除"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                deletedList
            }
            .onChange(of: visibleItemIDs) { _, ids in
                selectedItemIDs.formIntersection(ids)
            }
            .onChange(of: isSelectionMode) { _, _ in
                selectedItemIDs.removeAll()
                pendingPermanentDeleteIDs.removeAll()
            }
            .confirmationDialog(
                AppLocalizer.format(
                    "diary.recentlyDeleted.permanentDeleteConfirmation",
                    pendingPermanentDeleteIDs.count
                ),
                isPresented: $showPermanentDeleteConfirmation
            ) {
                Button(AppLocalizer.string("彻底删除"), role: .destructive) {
                    permanentlyDeleteSelected()
                }
                Button(AppLocalizer.string("取消"), role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var deletedList: some View {
        if isSelectionMode {
            List {
                ForEach(store.recentlyDeletedItems) { item in
                    selectionRow(item)
                }
            }
            .listStyle(.inset)
        } else {
            List(store.recentlyDeletedItems) { item in
                normalRow(item)
            }
            .listStyle(.inset)
        }
    }

    private func normalRow(_ item: DiaryDeletedItem) -> some View {
        HStack(spacing: 12) {
            deletedItemSummary(item)
            Spacer()
            Button(AppLocalizer.string("恢复")) { Task { await store.restoreDeleted(id: item.id) } }
            Menu {
                Button(AppLocalizer.string("彻底删除…"), systemImage: "trash", role: .destructive) {
                    pendingPermanentDeleteIDs = [item.id]
                    showPermanentDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(AppLocalizer.string("更多操作"))
        }
        .padding(.vertical, 6)
    }

    private func selectionRow(_ item: DiaryDeletedItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.diaryAccent : .secondary)
                .font(.title3)
                .accessibilityHidden(true)
            deletedItemSummary(item)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleItemSelection(item.id) }
        .listRowBackground(isSelected ? Color.diarySelection : Color.clear)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggleItemSelection(item.id) }
        .accessibilityLabel(item.entry.displayTitle.isEmpty ? AppLocalizer.string("未命名日记") : item.entry.displayTitle)
        .accessibilityValue(AppLocalizer.string(isSelected ? "已选择" : "未选择"))
    }

    private func deletedItemSummary(_ item: DiaryDeletedItem) -> some View {
        HStack(spacing: 12) {
            Text(item.entry.mood?.emoji ?? "📝")
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.entry.displayTitle.isEmpty ? AppLocalizer.string("未命名日记") : item.entry.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(AppLocalizer.format(
                    "diary.recentlyDeleted.deletedAt",
                    item.deletedAt.formatted(date: .abbreviated, time: .shortened)
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleItemIDs: [UUID] {
        store.recentlyDeletedItems.map(\.id)
    }

    private var allItemsSelected: Bool {
        !visibleItemIDs.isEmpty && Set(visibleItemIDs).isSubset(of: selectedItemIDs)
    }

    private func toggleSelectAll() {
        let visibleIDs = Set(visibleItemIDs)
        if allItemsSelected {
            selectedItemIDs.subtract(visibleIDs)
        } else {
            selectedItemIDs.formUnion(visibleIDs)
        }
    }

    private func toggleItemSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func restore(_ ids: Set<UUID>) {
        selectedItemIDs.subtract(ids)
        guard !ids.isEmpty else { return }
        Task { _ = await store.restoreDeleted(ids: ids) }
    }

    private func permanentlyDeleteSelected() {
        let ids = pendingPermanentDeleteIDs
        pendingPermanentDeleteIDs.removeAll()
        selectedItemIDs.subtract(ids)
        guard !ids.isEmpty else { return }
        Task { _ = await store.permanentlyDelete(ids: ids) }
    }
}
