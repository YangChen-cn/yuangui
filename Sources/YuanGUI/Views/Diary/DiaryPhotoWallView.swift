import SwiftUI

struct DiaryPhotoWallView: View {
    @ObservedObject var store: DiaryFeature
    @State private var selected: PhotoSelection?
    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 210), spacing: 10)]

    private var photos: [PhotoSelection] {
        store.entries.sorted { $0.occurredAt > $1.occurredAt }.flatMap { entry in
            entry.attachments.map { PhotoSelection(entry: entry, attachment: $0) }
        }
    }

    var body: some View {
        if photos.isEmpty {
            ContentUnavailableView("还没有照片", systemImage: "photo.on.rectangle", description: Text("在日记中添加图片后会显示在这里。"))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(photos) { photo in
                        Button { selected = photo } label: {
                            PhotoCell(store: store, photo: photo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .sheet(item: $selected) { photo in
                DiaryAttachmentViewer(store: store, entry: photo.entry, attachment: photo.attachment) {
                    store.navigate(to: photo.entry.id)
                }
            }
        }
    }
}

private struct PhotoSelection: Identifiable {
    let entry: DiaryEntry
    let attachment: DiaryAttachment
    var id: UUID { attachment.id }
}

private struct PhotoCell: View {
    let store: DiaryFeature
    let photo: PhotoSelection
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary).overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(photo.entry.occurredAt.formatted(.dateTime.month().day()))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                .padding(7)
        }
        .task(id: photo.id) {
            guard let data = await store.thumbnailData(for: photo.attachment) else { return }
            image = NSImage(data: data)
        }
    }
}
