import SwiftUI

/// 日记列表行
struct DiaryEntryRow: View {
    let entry: DiaryEntry

    var body: some View {
        HStack(spacing: 10) {
            // 心情 emoji
            Text(entry.mood?.emoji ?? "📝")
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(dateText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    if !entry.tags.isEmpty {
                        Text(entry.tags.prefix(2).joined(separator: " "))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.pink.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(entry.occurredAt) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(entry.occurredAt) {
            return "昨天"
        } else {
            formatter.dateFormat = "M月d日"
            return formatter.string(from: entry.occurredAt)
        }
    }
}
