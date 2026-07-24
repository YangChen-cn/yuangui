import SwiftUI

struct DiaryRecentlyDeletedView: View {
    @ObservedObject var store: DiaryFeature
    @State private var pendingPermanentDelete: DiaryDeletedItem?

    var body: some View {
        if store.recentlyDeletedItems.isEmpty {
            ContentUnavailableView("最近删除为空", systemImage: "trash", description: Text("删除的日记会在这里保留 30 天。"))
        } else {
            List(store.recentlyDeletedItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.entry.displayTitle).font(.headline).lineLimit(1)
                        Text("删除于 \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("恢复") { Task { await store.restoreDeleted(id: item.id) } }
                    Button("彻底删除", role: .destructive) { pendingPermanentDelete = item }
                }
                .padding(.vertical, 4)
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
