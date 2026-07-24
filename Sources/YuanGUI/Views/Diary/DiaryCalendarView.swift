import SwiftUI

/// 日历浏览视图
struct DiaryCalendarView: View {
    @ObservedObject var store: DiaryFeature
    @State private var selectedMonth = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            // 月份导航
            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.plain)
                Spacer()
                Text(monthTitle).font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.plain)
            }

            // 星期头
            HStack {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 日期网格
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date {
                        DayCell(
                            date: date,
                            hasEntry: hasEntry(on: date),
                            isToday: calendar.isDateInToday(date)
                        ) {
                            selectDate(date)
                        }
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(16)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: selectedMonth)
    }

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: selectedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))
        else { return [] }

        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = weekday - 1

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    private func hasEntry(on date: Date) -> Bool {
        store.entries.contains { calendar.isDate($0.occurredAt, inSameDayAs: date) }
    }

    private func selectDate(_ date: Date) {
        if let entry = store.entries.first(where: { calendar.isDate($0.occurredAt, inSameDayAs: date) }) {
            store.selectedEntryID = entry.id
        }
    }

    private func changeMonth(_ offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
}

private struct DayCell: View {
    let date: Date
    let hasEntry: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(
                    isToday ? Color.pink : (hasEntry ? Color.pink.opacity(0.12) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    hasEntry && !isToday
                        ? Circle().fill(Color.pink).frame(width: 4, height: 4)
                        : nil,
                    alignment: .bottom
                )
        }
        .buttonStyle(.plain)
    }
}
