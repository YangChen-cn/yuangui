import SwiftUI

struct DiaryCalendarView: View {
    @ObservedObject var store: DiaryFeature
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMonth = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                monthHeader
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                        if let date {
                            DiaryCalendarDayCell(
                                date: date,
                                entries: entries(on: date),
                                isToday: calendar.isDateInToday(date),
                                action: { store.selectDay(date) }
                            )
                        } else {
                            Color.clear.frame(minHeight: 72)
                        }
                    }
                }
                .id(selectedMonth)
                .transition(.opacity)
            }
            .padding(DiaryDesign.pagePadding)
            .frame(maxWidth: DiaryDesign.pageMaximumWidth)
            .diaryPageStyle()
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.secondary.opacity(0.025))
    }

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                .help(AppLocalizer.string("上个月"))
                .accessibilityLabel(AppLocalizer.string("上个月"))
            Spacer()
            VStack(spacing: 3) {
                Text(selectedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                .help(AppLocalizer.string("下个月"))
                .accessibilityLabel(AppLocalizer.string("下个月"))
        }
        .buttonStyle(.borderless)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach([
                "diary.weekday.sunday",
                "diary.weekday.monday",
                "diary.weekday.tuesday",
                "diary.weekday.wednesday",
                "diary.weekday.thursday",
                "diary.weekday.friday",
                "diary.weekday.saturday"
            ], id: \.self) { day in
                Text(AppLocalizer.string(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: selectedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))
        else { return [] }

        let leadingBlanks = calendar.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        days += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: firstDay) }
        return days
    }

    private func entries(on date: Date) -> [DiaryEntry] {
        store.entries.filter { calendar.isDate($0.occurredAt, inSameDayAs: date) }
    }

    private func changeMonth(_ offset: Int) {
        guard let newDate = calendar.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: DiaryDesign.animationDuration)) {
            selectedMonth = newDate
        }
    }
}

private struct DiaryCalendarDayCell: View {
    let date: Date
    let entries: [DiaryEntry]
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.subheadline.weight(isToday ? .bold : .medium))
                    Spacer(minLength: 2)
                    if let mood = entries.first?.mood {
                        Text(mood.emoji).font(.caption)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    if !entries.isEmpty {
                        Text(AppLocalizer.format("diary.list.entryCount", entries.count))
                    }
                    if entries.contains(where: { !$0.attachments.isEmpty }) {
                        Image(systemName: "photo.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(entries.isEmpty ? Color.clear : Color.diarySelection)
            .clipShape(RoundedRectangle(cornerRadius: DiaryDesign.smallCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DiaryDesign.smallCornerRadius)
                    .stroke(isToday ? Color.diaryAccent : Color.diaryBorder, lineWidth: isToday ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let dateText = date.formatted(.dateTime.month().day())
        let moodText = entries.first?.mood?.title ?? ""
        let entryCount = AppLocalizer.format("diary.list.entryCount", entries.count)
        let mood = moodText.isEmpty ? "" : "，\(AppLocalizer.string("心情"))\(moodText)"
        return "\(dateText)，\(entryCount)\(mood)"
    }
}
