import SwiftUI

struct DiaryPhotoGrid: View {
    let store: DiaryFeature
    let attachments: [DiaryAttachment]
    let onAdd: () -> Void
    let onOpen: (DiaryAttachment) -> Void
    let onRemove: (DiaryAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DiaryDesign.compactSpacing) {
            HStack {
                DiarySectionLabel(title: "照片", systemImage: "photo.on.rectangle")
                Spacer()
                Text("\(attachments.count)/\(DiaryAttachmentStore.maximumAttachmentsPerEntry)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if attachments.isEmpty {
                Button(action: onAdd) {
                Label(AppLocalizer.string("添加照片，或从 Finder 拖到这里"), systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.bordered)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(attachments) { attachment in
                        DiaryAttachmentThumbnail(
                            store: store,
                            attachment: attachment,
                            aspectRatio: attachments.count == 1 ? 16 / 9 : 1,
                            onOpen: { onOpen(attachment) },
                            onRemove: { onRemove(attachment) }
                        )
                    }
                }
                Button(AppLocalizer.string("添加更多照片"), systemImage: "plus", action: onAdd)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.diaryAccent)
            }
        }
    }

    private var columns: [GridItem] {
        if attachments.count == 1 {
            return [GridItem(.flexible())]
        }
        if attachments.count == 2 {
            return Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        }
        return [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 10)]
    }
}

struct DiaryAttachmentThumbnail: View {
    let store: DiaryFeature
    let attachment: DiaryAttachment
    let aspectRatio: CGFloat
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var image: NSImage?
    @State private var didFinishLoading = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Button(action: onOpen) {
                ZStack {
                    Color.diarySecondarySurface
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    } else if didFinishLoading {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.tertiary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DiaryDesign.cardCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DiaryDesign.cardCornerRadius, style: .continuous)
                        .stroke(Color.diaryBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看照片 \(attachment.originalFilename)")

            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
            .help(AppLocalizer.string("查看大图"))
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                    }
            .help(AppLocalizer.string("移除照片"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .background(.black.opacity(0.04))
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(AppLocalizer.string("查看大图"), systemImage: "arrow.up.left.and.arrow.down.right", action: onOpen)
            Button(AppLocalizer.string("移除照片"), systemImage: "trash", role: .destructive, action: onRemove)
        }
        .accessibilityAction(named: AppLocalizer.string("查看大图"), onOpen)
        .accessibilityAction(named: AppLocalizer.string("移除照片"), onRemove)
        .task(id: attachment.id) {
            if let data = await store.thumbnailData(for: attachment) {
                image = NSImage(data: data)
            }
            didFinishLoading = true
        }
    }
}

struct DiaryAttachmentViewer: View {
    let store: DiaryFeature
    let entry: DiaryEntry
    let attachment: DiaryAttachment
    let onOpenEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var didFinishLoading = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayTitle).font(.headline)
                    Text(entry.occurredAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help(AppLocalizer.string("关闭"))
                    .accessibilityLabel(AppLocalizer.string("关闭照片"))
            }

            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else if didFinishLoading {
                    DiaryEmptyState(title: "无法载入照片", message: "原图可能已被移动或损坏。", systemImage: "photo.badge.exclamationmark")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(AppLocalizer.string("打开所属日记"), systemImage: "book.pages") {
                onOpenEntry()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.diaryAccent)
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 480)
        .task {
            if let data = await store.attachmentData(for: attachment) {
                image = NSImage(data: data)
            }
            didFinishLoading = true
        }
    }
}
