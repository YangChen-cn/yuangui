import SwiftUI

struct DiaryRecentlyDeletedView: View {
    @ObservedObject var store: DiaryFeature
    @State private var pendingPermanentDelete: DiaryDeletedItem?

    var body: some View {
        if store.recentlyDeletedItems.isEmpty {
            DiaryEmptyState(
                title: "最近删除为空",
                message: "移除的日记会在这里保留 30 天。",
                systemImage: "trash"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近删除")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                List(store.recentlyDeletedItems) { item in
                    HStack(spacing: 12) {
                        Text(item.entry.mood?.emoji ?? "📝").font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.entry.displayTitle.isEmpty ? "未命名日记" : item.entry.displayTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text("删除于 \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") { Task { await store.restoreDeleted(id: item.id) } }
                        Menu {
                            Button("彻底删除…", systemImage: "trash", role: .destructive) {
                                pendingPermanentDelete = item
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("更多操作")
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
            .confirmationDialog("彻底删除后无法恢复", isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { if !$0 { pendingPermanentDelete = nil } }
            )) {
                Button("彻底删除", role: .destructive) {
                    guard let item = pendingPermanentDelete else { return }
                    Task { await store.permanentlyDelete(id: item.id) }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
