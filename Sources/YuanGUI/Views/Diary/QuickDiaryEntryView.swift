import SwiftUI

struct QuickDiaryEntryView: View {
    @ObservedObject var store: DiaryFeature
    let onSaved: () -> Void
    let onCancel: () -> Void
    let onOpenFullDiary: () -> Void
    private let recordedAt: Date

    @Environment(\.dismiss) private var dismiss
    @FocusState private var bodyIsFocused: Bool
    @State private var bodyText = ""
    @State private var mood: DiaryMood?
    @State private var momentWeather: DiaryWeatherSnapshot?
    @State private var momentMusic: DiaryMusicSnapshot?
    @State private var locationName: String
    @State private var tagText = ""
    @State private var tags: [String] = []
    @State private var imageURLs: [URL] = []
    @State private var clipboardImages: [DiaryImageDataSource] = []
    @State private var failures: [DiaryImageImportFailure] = []
    @State private var isSaving = false
    @State private var entryID: UUID?

    init(
        store: DiaryFeature,
        onSaved: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        onOpenFullDiary: @escaping () -> Void = {}
    ) {
        let recordedAt = Date()
        self.store = store
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onOpenFullDiary = onOpenFullDiary
        self.recordedAt = recordedAt
        _momentWeather = State(initialValue: store.currentWeatherSnapshot)
        _momentMusic = State(initialValue: store.currentMusicSnapshot)
        _locationName = State(initialValue: store.currentLocationName ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        DiarySectionLabel(title: "心情", systemImage: "face.smiling")
                        MoodPickerView(selectedMood: $mood)
                    }
                    DiaryMetadataSection(
                        weather: momentWeather,
                        music: momentMusic,
                        locationName: $locationName,
                        onUseCurrentLocation: { await store.requestCurrentLocationName() }
                    )
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
                }
                .padding(22)
            }
            Divider()
            saveBar
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 540, minHeight: 470)
        .tint(.diaryAccent)
        .dropDestination(for: URL.self) { urls, _ in
            imageURLs.append(contentsOf: urls)
            return !urls.isEmpty
        }
        .onAppear { bodyIsFocused = true }
        .onExitCommand { if !isSaving { cancel() } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("记录这一刻", systemImage: "heart.text.square.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.diaryAccent)
                Text(recordedAt.formatted(.dateTime.month(.wide).day().weekday(.wide).hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { cancel() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isSaving)
                .help(AppLocalizer.string("取消"))
                .accessibilityLabel(AppLocalizer.string("取消快速记录"))
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
                    Text(AppLocalizer.string("今天发生了什么…"))
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(AppLocalizer.string("快速记录正文"))
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiarySectionLabel(title: "标签", systemImage: "tag")
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    DiaryTagChip(tag: tag) { tags.removeAll { $0 == tag } }
                }
                TextField(AppLocalizer.string("添加标签"), text: $tagText)
                    .textFieldStyle(.plain)
                    .frame(width: 90)
                    .onSubmit(addTag)
            }
        }
    }

    private var photoActions: some View {
        HStack(spacing: 12) {
            Button(AppLocalizer.string("选择照片"), systemImage: "photo.badge.plus") {
                imageURLs.append(contentsOf: DiaryPanelService.chooseImages())
            }
            Button { pasteImage() } label: { Image(systemName: "doc.on.clipboard") }
                .help(AppLocalizer.string("从剪贴板添加照片"))
                .accessibilityLabel(AppLocalizer.string("从剪贴板添加照片"))
            if pendingPhotoCount > 0 {
                Label(AppLocalizer.format("diary.quickEntry.pendingPhotos", pendingPhotoCount), systemImage: "photo.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .buttonStyle(.borderless)
    }

    private var saveBar: some View {
        HStack {
            Button(AppLocalizer.string("完整编辑"), systemImage: "rectangle.split.3x1") { continueInFullDiary() }
                .disabled(isSaving)
            Spacer()
            Button(AppLocalizer.string(isSaving ? "保存中…" : "保存这一刻"), systemImage: "checkmark") { save() }
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
            failures = [DiaryImageImportFailure(
                name: AppLocalizer.string("剪贴板"),
                message: AppLocalizer.string("没有可用图片")
            )]
            return
        }
        clipboardImages.append(image)
    }

    private func save() {
        isSaving = true
        Task {
            let entry = prepareEntry()
            let importFailures = await importPendingImages(to: entry.id)
            failures = importFailures
            let didSave = await store.completeEditingSession(id: entry.id)
            if didSave {
                if !importFailures.isEmpty {
                    store.operationError = importFailures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n")
                }
                onSaved()
                dismiss()
            } else {
                failures.insert(DiaryImageImportFailure(
                    name: AppLocalizer.string("日记"),
                    message: AppLocalizer.string("保存失败，请重试")
                ), at: 0)
                isSaving = false
            }
        }
    }

    private func continueInFullDiary() {
        isSaving = true
        Task {
            let entry = prepareEntry()
            let importFailures = await importPendingImages(to: entry.id)
            if !importFailures.isEmpty {
                store.operationError = importFailures.map { "\($0.name)：\($0.message)" }.joined(separator: "\n")
            }
            onOpenFullDiary()
            dismiss()
        }
    }

    private func prepareEntry() -> DiaryEntry {
        let entry: DiaryEntry
        if let entryID, let existing = store.entries.first(where: { $0.id == entryID }) {
            entry = existing
        } else {
            var created = store.createEntry(occurredAt: recordedAt)
            created.weather = momentWeather
            created.music = momentMusic
            store.updateEntry(created)
            entryID = created.id
            entry = created
        }
        var draft = DiaryDraft(entry: entry)
        draft.body = bodyText
        draft.mood = mood
        draft.tags = tags
        draft.locationName = locationName
        store.updateDraft(draft)
        return entry
    }

    private func importPendingImages(to entryID: UUID) async -> [DiaryImageImportFailure] {
        var importFailures = await store.addImages(to: entryID, urls: imageURLs)
        importFailures += await store.addImageDataSources(to: entryID, sources: clipboardImages)
        imageURLs.removeAll()
        clipboardImages.removeAll()
        return importFailures
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}
