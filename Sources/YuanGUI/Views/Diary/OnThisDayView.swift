import SwiftUI

/// 那年今日视图
struct OnThisDayView: View {
    @ObservedObject var store: DiaryFeature

    var body: some View {
        let entries = store.onThisDayEntries

        if entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("还没有往年的今日回忆")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("一年后的今天，这里会显示你今天写下的日记")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.pink)
                        Text("那年今日")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    ForEach(entries) { entry in
                        OnThisDayCard(entry: entry) {
                            store.navigate(to: entry.id)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct OnThisDayCard: View {
    let entry: DiaryEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.mood?.emoji ?? "📝")
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayTitle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(dateText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(entry.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.pink.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        let years = max(Calendar.current.dateComponents([.year], from: entry.occurredAt, to: Date()).year ?? 1, 1)
        return "\(years) 年前 · \(formatter.string(from: entry.occurredAt))"
    }
}
