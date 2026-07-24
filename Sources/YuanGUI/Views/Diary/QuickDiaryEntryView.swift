import SwiftUI

struct QuickDiaryEntryView: View {
    @ObservedObject var store: DiaryFeature
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("记录这一刻").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(isSaving)
            }
            MoodPickerView(selectedMood: $mood)
            TextEditor(text: $bodyText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("今天发生了什么…").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false)
                    }
                }
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text("#\(tag)").font(.caption)
                        Button { tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.pink.opacity(0.1), in: Capsule())
                }
                TextField("标签", text: $tagText).textFieldStyle(.plain).frame(width: 70).onSubmit(addTag)
            }
            HStack {
                Button { imageURLs.append(contentsOf: DiaryPanelService.chooseImages()) } label: {
                    Label("照片", systemImage: "photo.badge.plus")
                }
                Button { pasteImage() } label: { Image(systemName: "doc.on.clipboard") }.help("从剪贴板添加")
                if !imageURLs.isEmpty || !clipboardImages.isEmpty {
                    Text("\(imageURLs.count + clipboardImages.count) 张待导入").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(isSaving || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !failures.isEmpty {
                Text(failures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(minWidth: 430, idealWidth: 430, maxWidth: 430, minHeight: 340)
        .dropDestination(for: URL.self) { urls, _ in
            imageURLs.append(contentsOf: urls)
            return !urls.isEmpty
        }
    }

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
