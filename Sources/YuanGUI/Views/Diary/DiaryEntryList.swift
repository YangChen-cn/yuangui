import SwiftUI

/// 日记列表
struct DiaryEntryList: View {
    @ObservedObject var store: DiaryFeature
    let onCreateNew: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("搜索日记…", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

            // 列表
            if store.filteredEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(emptyText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Button("记录这一刻") { onCreateNew() }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        .controlSize(.small)
                }
                Spacer()
            } else {
                List(store.filteredEntries, selection: $store.selectedEntryID) { entry in
                    DiaryEntryRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(entry.isFavorite ? "取消收藏" : "收藏") {
                                store.toggleFavorite(id: entry.id)
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                store.deleteEntry(id: entry.id)
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 260)
    }

    private var emptyText: String {
        if !store.searchText.isEmpty {
            return "没有找到匹配的日记"
        } else if store.showFavoritesOnly {
            return "还没有收藏的日记"
        } else if let tag = store.activeTag {
            return "没有标签为 #\(tag) 的日记"
        } else {
            return "还没有日记"
        }
    }
}
