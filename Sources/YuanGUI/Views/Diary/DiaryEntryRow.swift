import SwiftUI

struct DiaryEntryRow: View {
    let store: DiaryFeature
    let entry: DiaryEntry
    @State private var coverImage: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.mood?.emoji ?? "📝")
                .font(.title3)
                .frame(width: 26)
                .accessibilityLabel(entry.mood?.title ?? "未记录心情")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.displayTitle.isEmpty ? "未命名日记" : entry.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("已收藏")
                    }
                }

                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 7) {
                    Text(entry.occurredAt.formatted(date: .omitted, time: .shortened))
                    ForEach(entry.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .foregroundStyle(Color.diaryAccent)
                    }
                    if !entry.attachments.isEmpty {
                        Label("\(entry.attachments.count)", systemImage: "photo")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            if !entry.attachments.isEmpty {
                cover
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .task(id: entry.attachments.first?.id) {
            guard let attachment = entry.attachments.first,
                  let data = await store.thumbnailData(for: attachment)
            else {
                coverImage = nil
                return
            }
            coverImage = NSImage(data: data)
        }
    }

    private var cover: some View {
        Group {
            if let coverImage {
                Image(nsImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.diarySecondarySurface
                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: DiaryDesign.smallCornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var summary: String? {
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, entry.title != nil else { return nil }
        return body.replacingOccurrences(of: "\n", with: " ")
    }
}
