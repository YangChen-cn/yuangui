import SwiftUI

struct DiaryPhotoWallView: View {
    @ObservedObject var store: DiaryFeature
    @State private var selected: PhotoSelection?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 12)]

    private var photos: [PhotoSelection] {
        store.entries.sorted { $0.occurredAt > $1.occurredAt }.flatMap { entry in
            entry.attachments.map { PhotoSelection(entry: entry, attachment: $0) }
        }
    }

    var body: some View {
        if photos.isEmpty {
            DiaryEmptyState(
                title: "还没有照片",
                message: "照片会按记录时间汇成你们的回忆相册。",
                systemImage: "photo.on.rectangle",
                actionTitle: "记录这一刻"
            ) {
                _ = store.createEntry()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(photos) { photo in
                            Button { selected = photo } label: {
                                DiaryPhotoWallCell(store: store, photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1_020)
                .frame(maxWidth: .infinity)
            }
            .background(Color.secondary.opacity(0.025))
            .sheet(item: $selected) { photo in
                DiaryAttachmentViewer(store: store, entry: photo.entry, attachment: photo.attachment) {
                    store.navigate(to: photo.entry.id)
                }
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalizer.string("照片墙")).font(.title2.weight(.semibold))
                Text(AppLocalizer.format("diary.photoWall.photoCount", photos.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct PhotoSelection: Identifiable {
    let entry: DiaryEntry
    let attachment: DiaryAttachment
    var id: UUID { attachment.id }
}

private struct DiaryPhotoWallCell: View {
    let store: DiaryFeature
    let photo: PhotoSelection

    @State private var image: NSImage?
    @State private var didFinishLoading = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                photoContent
                if isHovering {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(photo.entry.displayTitle.isEmpty ? AppLocalizer.string("未命名日记") : photo.entry.displayTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(photo.entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.55))
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DiaryDesign.cardCornerRadius, style: .continuous))

            HStack(spacing: 5) {
                Text(photo.entry.mood?.emoji ?? "")
                Text(photo.entry.occurredAt.formatted(.dateTime.year().month().day()))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(photo.entry.occurredAt.formatted(date: .long, time: .omitted)), " +
            (photo.entry.displayTitle.isEmpty ? AppLocalizer.string("未命名日记") : photo.entry.displayTitle)
        )
        .task(id: photo.id) {
            if let data = await store.thumbnailData(for: photo.attachment) {
                image = NSImage(data: data)
            }
            didFinishLoading = true
        }
    }

    private var photoContent: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            } else if didFinishLoading {
                Color.diarySecondarySurface
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Color.diarySecondarySurface
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.diarySecondarySurface)
    }
}
