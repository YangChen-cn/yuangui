import SwiftUI
import UniformTypeIdentifiers

struct DiaryDetailEditView: View {
    @ObservedObject var store: DiaryFeature
    let entry: DiaryEntry
    let isFocusMode: Bool
    let onFocusModeChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @State private var draft: DiaryDraft
    @State private var editorMode: DiaryEditorMode = .edit
    @State private var newTag = ""
    @State private var showDeleteConfirmation = false
    @State private var importFailures: [DiaryImageImportFailure] = []
    @State private var selectedAttachment: DiaryAttachment?

    init(
        store: DiaryFeature,
        entry: DiaryEntry,
        isFocusMode: Bool = false,
        onFocusModeChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.entry = entry
        self.isFocusMode = isFocusMode
        self.onFocusModeChange = onFocusModeChange
        _draft = State(initialValue: DiaryDraft(entry: entry))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiaryDesign.sectionSpacing) {
                pageHeader
                Divider().opacity(0.65)
                DiaryMetadataSection(
                    weather: entry.weather,
                    music: entry.music,
                    locationName: $draft.locationName,
                    onUseCurrentLocation: { await store.requestCurrentLocationName() }
                )
                titleEditor
                bodyEditor
                DiaryPhotoGrid(
                    store: store,
                    attachments: entry.attachments,
                    onAdd: chooseImages,
                    onOpen: { selectedAttachment = $0 },
                    onRemove: { attachment in
                        Task { await store.removeAttachment(from: entry.id, attachmentID: attachment.id) }
                    }
                )
                tagEditor
                pageFooter
            }
            .padding(DiaryDesign.pagePadding)
            .frame(maxWidth: DiaryDesign.pageMaximumWidth, alignment: .leading)
            .diaryPageStyle()
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Color.secondary.opacity(0.025))
        .dropDestination(for: URL.self) { urls, _ in
            importImages(urls)
            return !urls.isEmpty
        }
        .onChange(of: draft) { _, value in store.updateDraft(value) }
        .onDisappear {
            Task { await store.completeEditingSession(id: entry.id) }
        }
        .onExitCommand {
            if isFocusMode { onFocusModeChange(false) }
        }
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

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.occurredAt.formatted(.dateTime.year().month(.wide).day()))
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Text(draft.occurredAt.formatted(.dateTime.weekday(.wide)))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(draft.occurredAt.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            MoodPickerView(selectedMood: $draft.mood)
                .frame(minWidth: 120, maxWidth: 310)
                .accessibilityLabel("心情")

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button { changeEditorMode() } label: {
                    Image(systemName: editorMode == .edit ? "eye" : "pencil")
                }
                .help(editorMode == .edit ? "预览" : "编辑")
                .accessibilityLabel(editorMode == .edit ? "预览日记" : "编辑日记")

                Button { onFocusModeChange(!isFocusMode) } label: {
                    Image(systemName: isFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help(isFocusMode ? "退出专注模式" : "进入专注模式")
                .accessibilityLabel(isFocusMode ? "退出专注模式" : "进入专注模式")

                Button { store.toggleFavorite(id: entry.id) } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                }
                .help(entry.isFavorite ? "取消收藏" : "收藏")
                .accessibilityLabel(entry.isFavorite ? "取消收藏" : "收藏")

                Menu {
                    Button("添加照片…", systemImage: "photo.badge.plus", action: chooseImages)
                    Button("从剪贴板添加", systemImage: "doc.on.clipboard", action: pasteImage)
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                    Divider()
                    Button("移到最近删除…", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多操作")
                .accessibilityLabel("更多操作")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: DiaryDesign.animationDuration), value: isFocusMode)
    }

    private var titleEditor: some View {
        TextField("为这一刻写个标题（可选）", text: $draft.title)
            .textFieldStyle(.plain)
            .font(.title.weight(.semibold))
            .accessibilityLabel("日记标题")
    }

    @ViewBuilder
    private var bodyEditor: some View {
        if editorMode == .preview {
            DiaryMarkdownPreview(markdown: draft.body)
                .frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading)
                .transition(.opacity)
        } else {
            DiaryGrowingTextEditor(
                text: $draft.body,
                minimumHeight: 340,
                onPasteImage: pasteImageIfAvailable
            )
                .overlay(alignment: .topLeading) {
                    if draft.body.isEmpty {
                        Text("写下今天发生的事…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 7)
                            .allowsHitTesting(false)
                    }
                }
                .transition(.opacity)
                .accessibilityLabel("日记正文")
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: DiaryDesign.compactSpacing) {
            DiarySectionLabel(title: "标签", systemImage: "tag")
            FlowLayout(spacing: 6) {
                ForEach(draft.tags, id: \.self) { tag in
                    DiaryTagChip(tag: tag) {
                        draft.tags.removeAll { $0 == tag }
                    }
                }
                TextField("添加标签", text: $newTag)
                    .textFieldStyle(.plain)
                    .frame(width: 90)
                    .onSubmit(addTag)
            }
        }
    }

    private var pageFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !importFailures.isEmpty {
                Label(
                    importFailures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            HStack {
                Text("\(draft.body.count) 字")
                    .foregroundStyle(.tertiary)
                Spacer()
                DiarySaveStatusView(state: store.saveState) {
                    Task { _ = await store.flush() }
                }
            }
            .font(.caption)
        }
    }

    private func changeEditorMode() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: DiaryDesign.animationDuration)) {
            editorMode = editorMode == .edit ? .preview : .edit
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
        guard pasteImageIfAvailable() else {
            importFailures = [DiaryImageImportFailure(name: "剪贴板", message: "没有可用图片")]
            return
        }
    }

    private func pasteImageIfAvailable() -> Bool {
        guard let image = DiaryPanelService.clipboardImage() else { return false }
        Task { importFailures = await store.addImageDataSources(to: entry.id, sources: [image]) }
        return true
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

private enum DiaryEditorMode {
    case edit
    case preview
}
