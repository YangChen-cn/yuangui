import SwiftUI

struct DiaryEntryListHeader: View {
    @ObservedObject var store: DiaryFeature
    @Binding var isSelectionMode: Bool
    let selectedCount: Int
    let allVisibleEntriesSelected: Bool
    let toggleSelectAll: () -> Void

    var body: some View {
        HStack {
            Text(listTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isSelectionMode {
                if !store.filteredEntries.isEmpty {
                    Button(action: toggleSelectAll) {
                        Image(systemName: allVisibleEntriesSelected ? "minus.square" : "checkmark.square")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 26, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(AppLocalizer.string(allVisibleEntriesSelected ? "取消选择当前列表" : "选择当前列表"))
                    .accessibilityLabel(AppLocalizer.string(allVisibleEntriesSelected ? "反全选" : "全选"))
                }
                if selectedCount > 0 {
                    Text(AppLocalizer.format("diary.list.selectedCount", selectedCount))
                        .foregroundStyle(.tertiary)
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
                .help(AppLocalizer.string("选择多篇日记"))
            }
            Text(AppLocalizer.format("diary.list.entryCount", store.filteredEntries.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var listTitle: String {
        if !store.searchText.isEmpty { return AppLocalizer.string("搜索结果") }
        if store.filter.favoritesOnly { return AppLocalizer.string("收藏") }
        if let tag = store.filter.tag { return "#\(tag)" }
        if let day = store.filter.day { return day.formatted(.dateTime.month().day()) }
        if let month = store.filter.month { return month.formatted(.dateTime.year().month(.wide)) }
        return AppLocalizer.string("时间线")
    }
}
