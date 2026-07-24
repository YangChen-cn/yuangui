import SwiftUI

struct DiaryEntryList: View {
    @ObservedObject var store: DiaryFeature
    let onCreateNew: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var pendingDelete: DiaryEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索日记…", text: $store.searchText).textFieldStyle(.plain)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            .padding(8)

            if store.filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label("还没有写下今天的故事", systemImage: "book.closed")
                } description: {
                    Text("记录一件刚刚发生的小事吧。")
                } actions: {
                    Button("记录这一刻", systemImage: "square.and.pencil", action: onCreateNew)
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                }
            } else {
                List(store.filteredEntries, selection: $store.selectedEntryID) { entry in
                    DiaryEntryRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(entry.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(id: entry.id) }
                            Divider()
                            Button("删除…", role: .destructive) { pendingDelete = entry }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .confirmationDialog("将这篇日记移到最近删除？", item: $pendingDelete) { entry in
            Button("移到最近删除", role: .destructive) { delete(entry) }
            Button("取消", role: .cancel) {}
        }
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

private extension View {
    func confirmationDialog<Item>(
        _ title: String,
        item: Binding<Item?>,
        @ViewBuilder actions: @escaping (Item) -> some View
    ) -> some View {
        confirmationDialog(title, isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let value = item.wrappedValue { actions(value) }
        }
    }
}
