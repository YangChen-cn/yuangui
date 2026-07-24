import SwiftUI

/// 照片墙视图
struct DiaryPhotoWallView: View {
    @ObservedObject var store: DiaryFeature
    private let columns = Array(repeating: GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8), count: 3)

    var body: some View {
        let allAttachments = store.entries
            .sorted { $0.occurredAt > $1.occurredAt }
            .flatMap { entry in entry.attachments.map { (entry, $0) } }

        if allAttachments.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("还没有照片")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("在日记中添加图片后会显示在这里")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(allAttachments, id: \.1.id) { entry, attachment in
                        PhotoCell(attachment: attachment, date: entry.occurredAt)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct PhotoCell: View {
    let attachment: DiaryAttachment
    let date: Date
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minHeight: 120, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .frame(height: 120)
                    .overlay(ProgressView().controlSize(.mini))
            }

            // 日期水印
            Text(dateWatermark)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
        .onAppear { load() }
    }

    private var dateWatermark: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func load() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thumbURL = appSupport
            .appendingPathComponent("YuanGUI/Diary/Attachments/Thumbnails")
            .appendingPathComponent(attachment.thumbnailFilename)
        if let data = try? Data(contentsOf: thumbURL) {
            image = NSImage(data: data)
        }
    }
}
