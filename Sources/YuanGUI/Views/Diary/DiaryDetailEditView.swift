import SwiftUI
import UniformTypeIdentifiers

struct DiaryDetailEditView: View {
    @ObservedObject var store: DiaryFeature
    let entry: DiaryEntry
    @Environment(\.undoManager) private var undoManager
    @State private var draft: DiaryDraft
    @State private var newTag = ""
    @State private var showPreview = false
    @State private var showDeleteConfirmation = false
    @State private var importFailures: [DiaryImageImportFailure] = []
    @State private var selectedAttachment: DiaryAttachment?

    init(store: DiaryFeature, entry: DiaryEntry) {
        self.store = store
        self.entry = entry
        _draft = State(initialValue: DiaryDraft(entry: entry))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        DatePicker("", selection: $draft.occurredAt, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                        MoodPickerView(selectedMood: $draft.mood)
                    }
                    HStack(spacing: 8) {
                        WeatherCardView(weather: entry.weather)
                        MusicCardView(music: entry.music)
                        Spacer()
                    }
                    TextField("标题（可选）", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Label {
                        TextField("地点（可选）", text: $draft.locationName).textFieldStyle(.plain)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                    }
                    tagEditor
                    if showPreview {
                        DiaryMarkdownPreview(markdown: draft.body).frame(minHeight: 260)
                    } else {
                        TextEditor(text: $draft.body)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260)
                    }
                    attachmentSection
                    if !importFailures.isEmpty {
                        Label(importFailures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dropDestination(for: URL.self) { urls, _ in
                importImages(urls)
                return !urls.isEmpty
            }
        }
        .onChange(of: draft) { _, value in store.updateDraft(value) }
        .confirmationDialog("将这篇日记移到最近删除？", isPresented: $showDeleteConfirmation) {
            Button("移到最近删除", role: .destructive) { deleteEntry() }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $selectedAttachment) { attachment in
            DiaryAttachmentViewer(store: store, entry: entry, attachment: attachment) {
                selectedAttachment = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(entry.mood?.emoji ?? "📝")
            Text(entry.displayTitle).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
            Spacer()
            Button { chooseImages() } label: { Image(systemName: "photo.badge.plus") }
                .help("添加照片")
            Button { pasteImage() } label: { Image(systemName: "doc.on.clipboard") }
                .help("从剪贴板添加照片")
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button { showPreview.toggle() } label: { Image(systemName: showPreview ? "pencil" : "eye") }
                .help(showPreview ? "编辑" : "预览")
            Button { store.toggleFavorite(id: entry.id) } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
            }
            .help(entry.isFavorite ? "取消收藏" : "收藏")
            Button { showDeleteConfirmation = true } label: { Image(systemName: "trash") }
                .foregroundStyle(.secondary)
                .help("删除")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var tagEditor: some View {
        FlowLayout(spacing: 6) {
            ForEach(draft.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(tag)").font(.caption)
                    Button { draft.tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.pink.opacity(0.1), in: Capsule())
            }
            TextField("添加标签", text: $newTag)
                .textFieldStyle(.plain)
                .frame(width: 80)
                .onSubmit { addTag() }
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("照片").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.attachments.count)/\(DiaryAttachmentStore.maximumAttachmentsPerEntry)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if entry.attachments.isEmpty {
                Button { chooseImages() } label: {
                    Label("添加照片，或从 Finder 拖到这里", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 70)
                }
                .buttonStyle(.bordered)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entry.attachments) { attachment in
                            DiaryAttachmentThumbnail(store: store, attachment: attachment) {
                                selectedAttachment = attachment
                            } onRemove: {
                                Task { await store.removeAttachment(from: entry.id, attachmentID: attachment.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let value = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        draft.tags.append(value)
        newTag = ""
    }

    private func chooseImages() {
        importImages(DiaryPanelService.chooseImages())
    }

    private func importImages(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { importFailures = await store.addImages(to: entry.id, urls: urls) }
    }

    private func pasteImage() {
        guard let image = DiaryPanelService.clipboardImage() else {
            importFailures = [DiaryImageImportFailure(name: "剪贴板", message: "没有可用图片")]
            return
        }
        Task { importFailures = await store.addImageDataSources(to: entry.id, sources: [image]) }
    }

    private func deleteEntry() {
        Task {
            guard let deleted = await store.deleteEntry(id: entry.id) else { return }
            undoManager?.registerUndo(withTarget: store) { target in
                Task { await target.restoreDeleted(id: deleted.id) }
            }
            undoManager?.setActionName("恢复日记")
        }
    }
}

struct DiaryAttachmentThumbnail: View {
    let store: DiaryFeature
    let attachment: DiaryAttachment
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.45))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .task(id: attachment.id) {
            guard let data = await store.thumbnailData(for: attachment) else { return }
            image = NSImage(data: data)
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

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.displayTitle).font(.headline)
                    Text(entry.occurredAt.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("打开所属日记") {
                onOpenEntry()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 480)
        .task {
            guard let data = await store.attachmentData(for: attachment) else { return }
            image = NSImage(data: data)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.offsets[index].x, y: bounds.minY + result.offsets[index].y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, cursor.x - spacing)
        }
        return (offsets, CGSize(width: width, height: cursor.y + lineHeight))
    }
}
