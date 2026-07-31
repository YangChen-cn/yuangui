import SwiftUI

private enum DiarySidebarSelection: Hashable {
    case timeline
    case calendar
    case photoWall
    case onThisDay
    case favorites
    case recentlyDeleted
    case month(Date)
    case tag(String)
}

struct DiarySidebarView: View {
    @ObservedObject var store: DiaryFeature
    @State private var selection: DiarySidebarSelection?

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            List(selection: $selection) {
                Section(AppLocalizer.string("回忆")) {
                    Label("时间线", systemImage: "text.justify.left")
                        .tag(DiarySidebarSelection.timeline)
                    Label("日历", systemImage: "calendar")
                        .tag(DiarySidebarSelection.calendar)
                    Label("照片墙", systemImage: "photo.on.rectangle.angled")
                        .tag(DiarySidebarSelection.photoWall)
                    Label("那年今日", systemImage: "clock.arrow.circlepath")
                        .tag(DiarySidebarSelection.onThisDay)
                    Label("收藏", systemImage: "star")
                        .tag(DiarySidebarSelection.favorites)
                    Label("最近删除", systemImage: "trash")
                        .tag(DiarySidebarSelection.recentlyDeleted)
                }

                Section(AppLocalizer.string("月份")) {
                    ForEach(availableMonths, id: \.self) { month in
                        Label(
                            month.formatted(.dateTime.year().month(.wide)),
                            systemImage: "calendar.day.timeline.left"
                        )
                        .tag(DiarySidebarSelection.month(month))
                    }
                }

                if !store.allTags.isEmpty {
                    Section(AppLocalizer.string("标签")) {
                        ForEach(store.allTags, id: \.self) { tag in
                            Label("#\(tag)", systemImage: "tag")
                                .tag(DiarySidebarSelection.tag(tag))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selection) { _, newSelection in
                apply(newSelection)
            }
            .onAppear(perform: synchronizeSelection)
            .onChange(of: store.viewMode) { _, _ in synchronizeSelection() }
            .onChange(of: store.filter) { _, _ in synchronizeSelection() }
            sidebarFooter
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(Color.diaryAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalizer.string("手帐本"))
                    .font(.headline)
                Text(AppLocalizer.string("珍藏属于我们的日常"))
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
            Label(AppLocalizer.format("diary.sidebar.entryCount", store.entries.count), systemImage: "book.closed")
            Label(AppLocalizer.format("diary.sidebar.photoCount", photoCount), systemImage: "photo")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(
            "\(AppLocalizer.format("diary.sidebar.entryCount", store.entries.count)), " +
            AppLocalizer.format("diary.sidebar.photoCount", photoCount)
        )
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

    private func apply(_ selection: DiarySidebarSelection?) {
        guard let selection else { return }
        switch selection {
        case .timeline:
            store.clearFilters()
            store.viewMode = .timeline
        case .calendar:
            store.viewMode = .calendar
        case .photoWall:
            store.viewMode = .photoWall
        case .onThisDay:
            store.viewMode = .onThisDay
        case .favorites:
            store.filter = DiaryFilter(favoritesOnly: true)
            store.viewMode = .timeline
        case .recentlyDeleted:
            store.viewMode = .recentlyDeleted
        case .month(let month):
            store.selectMonth(month)
        case .tag(let tag):
            store.filter = DiaryFilter(tag: tag)
            store.viewMode = .timeline
        }
    }

    private func synchronizeSelection() {
        switch store.viewMode {
        case .calendar:
            selection = .calendar
        case .photoWall:
            selection = .photoWall
        case .onThisDay:
            selection = .onThisDay
        case .recentlyDeleted:
            selection = .recentlyDeleted
        case .timeline:
            if store.filter.favoritesOnly {
                selection = .favorites
            } else if let tag = store.filter.tag {
                selection = .tag(tag)
            } else if let month = store.filter.month {
                selection = .month(month)
            } else {
                selection = .timeline
            }
        }
    }
}
