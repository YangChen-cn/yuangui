import SwiftUI

/// 日记详情编辑器
struct DiaryDetailEditView: View {
    @ObservedObject var store: DiaryFeature
    let entry: DiaryEntry

    @State private var entryTitle: String = ""
    @State private var entryBody: String = ""
    @State private var entryMood: DiaryMood? = nil
    @State private var entryTags: [String] = []
    @State private var newTag: String = ""
    @State private var showPreview: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部信息栏
            headerBar

            Divider()

            // 编辑区
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 日期 + 心情
                    HStack(spacing: 8) {
                        DatePicker("", selection: binding(\.occurredAt), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .controlSize(.small)
                        MoodPickerView(selectedMood: $entryMood)
                    }

                    // 天气 + 音乐快照（独立行，不会被压缩）
                    HStack(spacing: 8) {
                        WeatherCardView(weather: entry.weather)
                        MusicCardView(music: entry.music)
                        Spacer()
                    }

                    // 标题
                    TextField("标题（可选）", text: $entryTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    // 标签
                    tagEditor

                    // 正文
                    if showPreview {
                        DiaryMarkdownPreview(markdown: entryBody)
                            .frame(minHeight: 200)
                    } else {
                        TextEditor(text: $entryBody)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 200)
                    }

                    // 附件
                    if !entry.attachments.isEmpty {
                        attachmentGrid
                    }
                }
                .padding(16)
            }
        }
        .onAppear { loadEntry() }
        .onChange(of: entry.id) { _, _ in loadEntry() }
        .onChange(of: entryTitle) { _, _ in save() }
        .onChange(of: entryBody) { _, _ in save() }
        .onChange(of: entryMood) { _, _ in save() }
        .onChange(of: entry.occurredAt) { _, _ in save() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text(entry.mood?.emoji ?? "📝")
                .font(.system(size: 16))
            Text(entry.displayTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()

            Button {
                showPreview.toggle()
            } label: {
                Image(systemName: showPreview ? "pencil" : "eye")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(showPreview ? "编辑" : "预览")

            Button {
                store.toggleFavorite(id: entry.id)
            } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(entry.isFavorite ? "取消收藏" : "收藏")

            Button {
                store.deleteEntry(id: entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tags

    private var tagEditor: some View {
        FlowLayout(spacing: 6) {
            ForEach(entryTags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(tag)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Button {
                        removeTag(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.pink.opacity(0.1), in: Capsule())
            }

            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("添加标签", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 60)
                    .onSubmit { addTag() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
    }

    // MARK: - Attachments

    private var attachmentGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("附件")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entry.attachments) { attachment in
                        AttachmentThumbnail(attachment: attachment, store: store, entryID: entry.id)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadEntry() {
        entryTitle = entry.title ?? ""
        entryBody = entry.body
        entryMood = entry.mood
        entryTags = entry.tags
    }

    private func save() {
        var updated = entry
        updated.title = entryTitle.isEmpty ? nil : entryTitle
        updated.body = entryBody
        updated.mood = entryMood
        updated.tags = entryTags
        store.updateEntry(updated)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !entryTags.contains(tag) else { return }
        entryTags.append(tag)
        newTag = ""
        save()
    }

    private func removeTag(_ tag: String) {
        entryTags.removeAll { $0 == tag }
        save()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DiaryEntry, T>) -> Binding<T> {
        Binding(
            get: { entry[keyPath: keyPath] },
            set: { newValue in
                var updated = entry
                updated[keyPath: keyPath] = newValue
                store.updateEntry(updated)
            }
        )
    }
}

// MARK: - Attachment Thumbnail

private struct AttachmentThumbnail: View {
    let attachment: DiaryAttachment
    let store: DiaryFeature
    let entryID: UUID
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    )
            }

            Button {
                store.removeAttachment(from: entryID, attachmentID: attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        // 简单加载：读取缩略图文件
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thumbURL = appSupport
            .appendingPathComponent("YuanGUI/Diary/Attachments/Thumbnails")
            .appendingPathComponent(attachment.thumbnailFilename)
        if let data = try? Data(contentsOf: thumbURL) {
            image = NSImage(data: data)
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (offsets, CGSize(width: maxX, height: y + rowHeight))
    }
}
