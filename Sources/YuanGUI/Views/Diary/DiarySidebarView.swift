import SwiftUI

/// 日记侧边栏：月份导航 + 标签 + 收藏
struct DiarySidebarView: View {
    @ObservedObject var store: DiaryFeature
    @State private var selectedMonth = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 月份导航
            HStack {
                Button {
                    changeMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)

                Spacer()
                Text(monthTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()

                Button {
                    changeMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            Divider()

            // 全部 & 收藏
            VStack(alignment: .leading, spacing: 4) {
                sidebarButton("全部日记", icon: "book.fill", isActive: !store.showFavoritesOnly) {
                    store.showFavoritesOnly = false
                    store.activeTag = nil
                }
                sidebarButton("收藏", icon: "star.fill", isActive: store.showFavoritesOnly) {
                    store.showFavoritesOnly = true
                    store.activeTag = nil
                }
            }

            Divider()

            // 标签
            if !store.allTags.isEmpty {
                Text("标签")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.allTags, id: \.self) { tag in
                            sidebarButton("#\(tag)", icon: "tag.fill", isActive: store.activeTag == tag) {
                                store.activeTag = store.activeTag == tag ? nil : tag
                                store.showFavoritesOnly = false
                            }
                        }
                    }
                }
            }

            Spacer()

            // 统计
            Text("\(store.entries.count) 条日记")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 180)
    }

    private func sidebarButton(_ title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? .pink : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isActive ? Color.pink.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: selectedMonth)
    }

    private func changeMonth(_ offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
}
