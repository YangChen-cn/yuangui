import SwiftUI

struct QuickDiaryEntryView: View {
    @ObservedObject var store: DiaryFeature
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var bodyIsFocused: Bool
    @State private var bodyText = ""
    @State private var mood: DiaryMood?
    @State private var tagText = ""
    @State private var tags: [String] = []
    @State private var imageURLs: [URL] = []
    @State private var clipboardImages: [DiaryImageDataSource] = []
    @State private var failures: [DiaryImageImportFailure] = []
    @State private var isSaving = false
    @State private var entryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(alignment: .leading, spacing: 8) {
                DiarySectionLabel(title: "心情", systemImage: "face.smiling")
                MoodPickerView(selectedMood: $mood)
            }
            bodyEditor
            tagsEditor
            photoActions
            if !failures.isEmpty {
                Label(
                    failures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            saveBar
        }
        .padding(22)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 540, minHeight: 400)
        .tint(.diaryAccent)
        .dropDestination(for: URL.self) { urls, _ in
            imageURLs.append(contentsOf: urls)
            return !urls.isEmpty
        }
        .onAppear { bodyIsFocused = true }
        .onExitCommand { if !isSaving { dismiss() } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("记录这一刻", systemImage: "heart.text.square.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.diaryAccent)
                Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isSaving)
                .help("取消")
                .accessibilityLabel("取消快速记录")
        }
    }

    private var bodyEditor: some View {
        TextEditor(text: $bodyText)
            .font(.body)
            .lineSpacing(5)
            .scrollContentBackground(.hidden)
            .focused($bodyIsFocused)
            .padding(8)
            .frame(minHeight: 140)
            .background(Color.diarySecondarySurface, in: RoundedRectangle(cornerRadius: DiaryDesign.cardCornerRadius))
            .overlay(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("今天发生了什么…")
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("快速记录正文")
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiarySectionLabel(title: "标签", systemImage: "tag")
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    DiaryTagChip(tag: tag) { tags.removeAll { $0 == tag } }
                }
                TextField("添加标签", text: $tagText)
                    .textFieldStyle(.plain)
                    .frame(width: 90)
                    .onSubmit(addTag)
            }
        }
    }

    private var photoActions: some View {
        HStack(spacing: 12) {
            Button("选择照片", systemImage: "photo.badge.plus") {
                imageURLs.append(contentsOf: DiaryPanelService.chooseImages())
            }
            Button { pasteImage() } label: { Image(systemName: "doc.on.clipboard") }
                .help("从剪贴板添加照片")
                .accessibilityLabel("从剪贴板添加照片")
            if pendingPhotoCount > 0 {
                Label("\(pendingPhotoCount) 张待导入", systemImage: "photo.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .buttonStyle(.borderless)
    }

    private var saveBar: some View {
        HStack {
            Spacer()
            Button(isSaving ? "保存中…" : "保存这一刻", systemImage: "checkmark") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var pendingPhotoCount: Int { imageURLs.count + clipboardImages.count }

    private func addTag() {
        let value = tagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        tags.append(value)
        tagText = ""
    }

    private func pasteImage() {
        guard let image = DiaryPanelService.clipboardImage() else {
            failures = [DiaryImageImportFailure(name: "剪贴板", message: "没有可用图片")]
            return
        }
        clipboardImages.append(image)
    }

    private func save() {
        isSaving = true
        Task {
            let entry: DiaryEntry
            if let entryID, let existing = store.entries.first(where: { $0.id == entryID }) {
                entry = existing
            } else {
                let created = store.createEntry()
                entryID = created.id
                entry = created
            }
            var draft = DiaryDraft(entry: entry)
            draft.body = bodyText
            draft.mood = mood
            draft.tags = tags
            store.updateDraft(draft)
            var importFailures = await store.addImages(to: entry.id, urls: imageURLs)
            importFailures += await store.addImageDataSources(to: entry.id, sources: clipboardImages)
            imageURLs.removeAll()
            clipboardImages.removeAll()
            failures = importFailures
            let didSave = await store.flush()
            if didSave {
                if !importFailures.isEmpty {
                    store.operationError = importFailures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n")
                }
                onSaved()
                dismiss()
            } else {
                failures.insert(DiaryImageImportFailure(name: "日记", message: "保存失败，请重试"), at: 0)
                isSaving = false
            }
        }
    }
}
