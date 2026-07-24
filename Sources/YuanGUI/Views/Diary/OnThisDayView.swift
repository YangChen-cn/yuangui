import SwiftUI

struct OnThisDayView: View {
    @ObservedObject var store: DiaryFeature

    var body: some View {
        if store.onThisDayEntries.isEmpty {
            DiaryEmptyState(
                title: "还没有往年的今日回忆",
                message: "以后回到这一天，今天写下的故事会在这里等你。",
                systemImage: "clock.arrow.circlepath"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("那年今日", systemImage: "clock.arrow.circlepath")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.diaryAccent)
                        Text(Date().formatted(.dateTime.month(.wide).day()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.onThisDayEntries) { entry in
                        OnThisDayCard(store: store, entry: entry) {
                            store.navigate(to: entry.id)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
            .background(Color.secondary.opacity(0.025))
        }
    }
}

private struct OnThisDayCard: View {
    let store: DiaryFeature
    let entry: DiaryEntry
    let onTap: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(yearsAgoText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.diaryAccent)
                        Text(entry.occurredAt.formatted(.dateTime.year().month(.wide).day()))
                            .font(.headline)
                    }
                    Spacer()
                    Text(entry.mood?.emoji ?? "📝").font(.title2)
                }

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                        .background(Color.diarySecondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: DiaryDesign.cardCornerRadius))
                }

                Text(entry.displayTitle.isEmpty ? "未命名日记" : entry.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                }
                metadata
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .diaryPageStyle()
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开这篇日记")
        .task(id: entry.attachments.first?.id) {
            guard let attachment = entry.attachments.first,
                  let data = await store.thumbnailData(for: attachment)
            else { return }
            image = NSImage(data: data)
        }
    }

    private var metadata: some View {
        FlowLayout(spacing: 12) {
            if let weather = entry.weather {
                Label("\(Int(weather.temperature))°C \(weather.condition)", systemImage: weather.icon)
            }
            if let music = entry.music {
                Label(music.title, systemImage: "music.note")
            }
            if let location = entry.locationName, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var yearsAgoText: String {
        let years = max(Calendar.current.dateComponents([.year], from: entry.occurredAt, to: Date()).year ?? 1, 1)
        return "\(years) 年前的今天"
    }
}
