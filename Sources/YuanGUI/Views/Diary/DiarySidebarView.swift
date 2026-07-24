import SwiftUI

struct DiarySidebarView: View {
    @ObservedObject var store: DiaryFeature

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            List {
                Section("回忆") {
                    navigationButton("时间线", icon: "text.justify.left", active: isAllTimeline) {
                        store.clearFilters()
                        store.viewMode = .timeline
                    }
                    navigationButton("日历", icon: "calendar", active: store.viewMode == .calendar) {
                        store.viewMode = .calendar
                    }
                    navigationButton("照片墙", icon: "photo.on.rectangle.angled", active: store.viewMode == .photoWall) {
                        store.viewMode = .photoWall
                    }
                    navigationButton("那年今日", icon: "clock.arrow.circlepath", active: store.viewMode == .onThisDay) {
                        store.viewMode = .onThisDay
                    }
                    navigationButton("收藏", icon: "star", active: store.viewMode == .timeline && store.filter.favoritesOnly) {
                        store.filter = DiaryFilter(favoritesOnly: true)
                        store.viewMode = .timeline
                    }
                    navigationButton("最近删除", icon: "trash", active: store.viewMode == .recentlyDeleted) {
                        store.viewMode = .recentlyDeleted
                    }
                }

                Section("月份") {
                    ForEach(availableMonths, id: \.self) { month in
                        navigationButton(
                            month.formatted(.dateTime.year().month(.wide)),
                            icon: "calendar.day.timeline.left",
                            active: isSelectedMonth(month)
                        ) {
                            store.selectMonth(month)
                        }
                    }
                }

                if !store.allTags.isEmpty {
                    Section("标签") {
                        ForEach(store.allTags, id: \.self) { tag in
                            navigationButton(
                                "#\(tag)",
                                icon: "tag",
                                active: store.viewMode == .timeline
                                    && store.filter.tag?.caseInsensitiveCompare(tag) == .orderedSame
                            ) {
                                store.filter = DiaryFilter(tag: tag)
                                store.viewMode = .timeline
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            sidebarFooter
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(Color.diaryAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("元圭恋爱手账")
                    .font(.headline)
                Text("珍藏属于我们的日常")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 12) {
            Label("\(store.entries.count)", systemImage: "book.closed")
            Label("\(photoCount)", systemImage: "photo")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(store.entries.count) 条日记，\(photoCount) 张照片")
    }

    private var isAllTimeline: Bool {
        store.viewMode == .timeline && store.filter == DiaryFilter()
    }

    private var photoCount: Int {
        store.entries.reduce(0) { $0 + $1.attachments.count }
    }

    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let entryMonths = store.entries.compactMap {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.occurredAt))
        }
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return Array(Set(entryMonths + [currentMonth])).sorted(by: >)
    }

    private func isSelectedMonth(_ month: Date) -> Bool {
        guard store.viewMode == .timeline, let selected = store.filter.month else { return false }
        return Calendar.current.isDate(month, equalTo: selected, toGranularity: .month)
    }

    private func navigationButton(
        _ title: String,
        icon: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(active ? AnyShapeStyle(Color.diaryAccent) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? Color.diarySelection : Color.clear)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
