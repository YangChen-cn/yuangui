import Combine
import Foundation

@MainActor
final class DiaryFeature: ObservableObject {
    enum ViewMode: String, CaseIterable, Identifiable, Sendable {
        case timeline = "时间线"
        case calendar = "日历"
        case photoWall = "照片墙"
        case onThisDay = "那年今日"
        case recentlyDeleted = "最近删除"
        var id: String { rawValue }
    }

    @Published var entries: [DiaryEntry] = []
    @Published var selectedEntryID: DiaryEntry.ID?
    @Published var searchText = "" {
        didSet { scheduleSearchUpdate() }
    }
    @Published var filter = DiaryFilter()
    @Published var viewMode: ViewMode = .timeline
    @Published private(set) var dirtyEntryIDs = Set<UUID>()
    @Published private(set) var loadState: DiaryLoadState = .unloaded
    @Published private(set) var saveState: DiarySaveState = .idle
    @Published private(set) var recoveredFiles: [URL] = []
    @Published private(set) var recentlyDeletedItems: [DiaryDeletedItem] = []
    @Published private(set) var backupStatus = DiaryBackupStatus.empty
    @Published private(set) var isBackupWorking = false
    @Published var operationError: String?

    private let repository: DiaryRepository
    private let attachmentStore: DiaryAttachmentStore
    private let exportService: DiaryExportService
    private let autoBackupService: DiaryAutoBackupService?
    let backupDirectoryURL: URL?
    private let searchService: DiarySearchService
    private weak var weatherService: WeatherService?
    private weak var musicFeature: MusicFeature?
    private var autoSaveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var autoBackupTask: Task<Void, Never>?
    private var debouncedSearchText = ""
    private var feedbackPendingEntryIDs = Set<UUID>()
    private var dirtyEntryRevisions: [UUID: UInt64] = [:]

    var onEntryCompleted: (() -> Void)?

    init(
        repository: DiaryRepository,
        attachmentStore: DiaryAttachmentStore,
        exportService: DiaryExportService,
        autoBackupService: DiaryAutoBackupService? = nil,
        backupDirectoryURL: URL? = nil,
        searchService: DiarySearchService,
        weatherService: WeatherService? = nil,
        musicFeature: MusicFeature? = nil
    ) {
        self.repository = repository
        self.attachmentStore = attachmentStore
        self.exportService = exportService
        self.autoBackupService = autoBackupService
        self.backupDirectoryURL = backupDirectoryURL
        self.searchService = searchService
        self.weatherService = weatherService
        self.musicFeature = musicFeature
    }

    convenience init(layout: DiaryStorageLayout, weatherService: WeatherService? = nil, musicFeature: MusicFeature? = nil) {
        let exportService = DiaryExportService(layout: layout)
        self.init(
            repository: DiaryRepository(layout: layout),
            attachmentStore: DiaryAttachmentStore(layout: layout),
            exportService: exportService,
            autoBackupService: DiaryAutoBackupService(
                layout: layout,
                exportService: exportService
            ),
            backupDirectoryURL: layout.backupURL,
            searchService: DiarySearchService(),
            weatherService: weatherService,
            musicFeature: musicFeature
        )
    }

    convenience init(weatherService: WeatherService? = nil, musicFeature: MusicFeature? = nil) {
        self.init(layout: .production, weatherService: weatherService, musicFeature: musicFeature)
    }

    var isDirty: Bool { !dirtyEntryIDs.isEmpty }
    var activeTag: String? {
        get { filter.tag }
        set { filter.tag = newValue }
    }
    var showFavoritesOnly: Bool {
        get { filter.favoritesOnly }
        set { filter.favoritesOnly = newValue }
    }

    var selectedEntry: DiaryEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    var currentWeatherSnapshot: DiaryWeatherSnapshot? {
        guard let weather = weatherService?.snapshot,
              weather.temperature > -50,
              weather.temperature < 60 else { return nil }
        return DiaryWeatherSnapshot(
            temperature: weather.temperature,
            condition: weather.condition.title,
            icon: weather.condition.symbol,
            capturedAt: Date()
        )
    }

    var currentMusicSnapshot: DiaryMusicSnapshot? {
        Self.diaryMusicSnapshot(
            track: musicFeature?.playback.currentTrack,
            isPlaying: musicFeature?.playback.isPlaying == true
        )
    }

    var currentLocationName: String? {
        normalizedLocationName(weatherService?.locationName)
    }

    var filteredEntries: [DiaryEntry] {
        var result = entries
        if !debouncedSearchText.isEmpty {
            result = searchService.search(query: debouncedSearchText, in: result)
        }
        if let tag = filter.tag { result = searchService.filter(entries: result, tag: tag) }
        if filter.favoritesOnly { result = searchService.favorites(in: result) }
        let calendar = Calendar.current
        if let day = filter.day {
            result = result.filter { calendar.isDate($0.occurredAt, inSameDayAs: day) }
        } else if let month = filter.month,
                  let interval = calendar.dateInterval(of: .month, for: month) {
            result = result.filter { interval.contains($0.occurredAt) }
        }
        return result.sorted { $0.occurredAt > $1.occurredAt }
    }

    var onThisDayEntries: [DiaryEntry] {
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let year = calendar.component(.year, from: today)
        return entries.filter {
            calendar.component(.year, from: $0.occurredAt) < year
                && calendar.component(.month, from: $0.occurredAt) == month
                && calendar.component(.day, from: $0.occurredAt) == day
        }.sorted { $0.occurredAt > $1.occurredAt }
    }

    var allTags: [String] {
        var seen = Set<String>()
        return entries.flatMap(\.tags).filter { seen.insert($0.lowercased()).inserted }.sorted()
    }

    func loadIfNeeded() async {
        guard loadState == .unloaded else { return }
        await loadFromDisk()
    }

    @discardableResult
    func reloadFromDisk() async -> Bool {
        guard await flush() else { return false }
        loadState = .unloaded
        await loadFromDisk()
        return loadState == .loaded
    }

    func createEntry(occurredAt: Date = Date()) -> DiaryEntry {
        var entry = DiaryEntry(occurredAt: occurredAt)
        entry.weather = currentWeatherSnapshot
        entry.music = currentMusicSnapshot
        entries.insert(entry, at: 0)
        selectedEntryID = entry.id
        return entry
    }

    @discardableResult
    func createAndOpenEntry(occurredAt: Date = Date()) -> DiaryEntry {
        clearFilters()
        viewMode = .timeline
        return createEntry(occurredAt: occurredAt)
    }

    func requestCurrentLocationName() async -> String? {
        guard let weatherService else { return nil }
        if let locationName = normalizedLocationName(weatherService.locationName) {
            return locationName
        }
        weatherService.start()
        weatherService.refresh()
        for _ in 0..<24 {
            if case .locationDenied = weatherService.status { return nil }
            try? await Task.sleep(for: .milliseconds(250))
            if let locationName = normalizedLocationName(weatherService.locationName) {
                return locationName
            }
        }
        return nil
    }

    static func diaryMusicSnapshot(
        track: MusicTrack?,
        isPlaying: Bool,
        capturedAt: Date = Date()
    ) -> DiaryMusicSnapshot? {
        guard isPlaying, let track, !track.title.isEmpty else { return nil }
        return DiaryMusicSnapshot(title: track.title, artist: track.artist, capturedAt: capturedAt)
    }

    func updateEntry(_ entry: DiaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.tags = normalizeTags(updated.tags)
        updated.updatedAt = Date()
        entries[index] = updated
        markDirty(entry.id)
    }

    func updateDraft(_ draft: DiaryDraft) {
        guard let index = entries.firstIndex(where: { $0.id == draft.id }) else { return }
        entries[index].title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.title
        entries[index].body = draft.body
        entries[index].occurredAt = draft.occurredAt
        entries[index].mood = draft.mood
        entries[index].tags = normalizeTags(draft.tags)
        let location = draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].locationName = location.isEmpty ? nil : location
        entries[index].updatedAt = Date()
        markDirty(draft.id)
    }

    func toggleFavorite(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isFavorite.toggle()
        entries[index].updatedAt = Date()
        markDirty(id)
    }

    func addImages(to entryID: UUID, urls: [URL]) async -> [DiaryImageImportFailure] {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return [] }
        let slots = DiaryAttachmentStore.maximumAttachmentsPerEntry - entries[index].attachments.count
        let prepared = await attachmentStore.prepare(urls: urls, availableSlots: slots)
        let result = await attachmentStore.save(prepared.images)
        if !result.attachments.isEmpty, let current = entries.firstIndex(where: { $0.id == entryID }) {
            entries[current].attachments.append(contentsOf: result.attachments)
            entries[current].updatedAt = Date()
            markDirty(entryID)
        }
        return prepared.failures + result.failures
    }

    func addPreparedImages(to entryID: UUID, images: [DiaryPreparedImage]) async -> [DiaryImageImportFailure] {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return [] }
        let available = max(DiaryAttachmentStore.maximumAttachmentsPerEntry - entries[index].attachments.count, 0)
        let accepted = Array(images.prefix(available))
        var failures: [DiaryImageImportFailure] = []
        if images.count > accepted.count {
            failures.append(DiaryImageImportFailure(name: "图片", message: "每篇日记最多添加 20 张图片"))
        }
        let result = await attachmentStore.save(accepted)
        if !result.attachments.isEmpty, let current = entries.firstIndex(where: { $0.id == entryID }) {
            entries[current].attachments.append(contentsOf: result.attachments)
            entries[current].updatedAt = Date()
            markDirty(entryID)
        }
        return failures + result.failures
    }

    func addImageDataSources(to entryID: UUID, sources: [DiaryImageDataSource]) async -> [DiaryImageImportFailure] {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return [] }
        let available = max(DiaryAttachmentStore.maximumAttachmentsPerEntry - entries[index].attachments.count, 0)
        let accepted = Array(sources.prefix(available))
        var prepared: [DiaryPreparedImage] = []
        var failures: [DiaryImageImportFailure] = []
        if sources.count > accepted.count {
            failures.append(DiaryImageImportFailure(name: "图片", message: "每篇日记最多添加 20 张图片"))
        }
        for source in accepted {
            do {
                prepared.append(try await attachmentStore.prepare(data: source.data, originalName: source.originalName))
            } catch {
                failures.append(DiaryImageImportFailure(name: source.originalName, message: error.localizedDescription))
            }
        }
        return failures + (await addPreparedImages(to: entryID, images: prepared))
    }

    func removeAttachment(from entryID: UUID, attachmentID: UUID) async {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              let attachment = entries[index].attachments.first(where: { $0.id == attachmentID }) else { return }
        entries[index].attachments.removeAll { $0.id == attachmentID }
        entries[index].updatedAt = Date()
        markDirty(entryID, schedule: false)
        let succeeded = await saveDirtyEntries(ids: [entryID])
        if succeeded {
            do { try await attachmentStore.remove(attachment) }
            catch { operationError = "附件引用已移除，但文件清理失败：\(error.localizedDescription)" }
        }
    }

    @discardableResult
    func deleteEntry(id: UUID) async -> DiaryDeletedItem? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        do {
            let deleted = try await repository.moveToRecentlyDeleted(entry)
            entries.removeAll { $0.id == id }
            dirtyEntryIDs.remove(id)
            dirtyEntryRevisions[id] = nil
            feedbackPendingEntryIDs.remove(id)
            if selectedEntryID == id { selectedEntryID = filteredEntries.first?.id ?? entries.first?.id }
            recentlyDeletedItems.insert(deleted, at: 0)
            return deleted
        } catch {
            operationError = "删除失败：\(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func deleteEntries(ids: Set<UUID>) async -> [DiaryDeletedItem] {
        var deletedItems: [DiaryDeletedItem] = []
        for id in ids {
            if let deleted = await deleteEntry(id: id) {
                deletedItems.append(deleted)
            }
        }
        return deletedItems
    }

    func restoreDeleted(id: UUID) async {
        do {
            let entry = try await repository.restoreDeleted(id: id)
            recentlyDeletedItems.removeAll { $0.id == id }
            entries.append(entry)
            entries.sort { $0.occurredAt > $1.occurredAt }
            navigate(to: entry.id)
        } catch {
            operationError = "恢复失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func restoreDeleted(ids: Set<UUID>) async -> Set<UUID> {
        var restoredIDs = Set<UUID>()
        for id in ids {
            let wasPresent = recentlyDeletedItems.contains { $0.id == id }
            await restoreDeleted(id: id)
            if wasPresent, !recentlyDeletedItems.contains(where: { $0.id == id }) {
                restoredIDs.insert(id)
            }
        }
        return restoredIDs
    }

    func permanentlyDelete(id: UUID) async {
        do {
            try await repository.permanentlyDelete(id: id)
            recentlyDeletedItems.removeAll { $0.id == id }
        } catch {
            operationError = "彻底删除失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func permanentlyDelete(ids: Set<UUID>) async -> Set<UUID> {
        var deletedIDs = Set<UUID>()
        for id in ids {
            let wasPresent = recentlyDeletedItems.contains { $0.id == id }
            await permanentlyDelete(id: id)
            if wasPresent, !recentlyDeletedItems.contains(where: { $0.id == id }) {
                deletedIDs.insert(id)
            }
        }
        return deletedIDs
    }

    func navigate(to id: UUID) {
        filter = DiaryFilter()
        selectedEntryID = id
        viewMode = .timeline
    }

    func selectMonth(_ month: Date?) {
        filter.day = nil
        filter.month = month
        viewMode = .timeline
    }

    func selectDay(_ day: Date) {
        let calendar = Calendar.current
        let matches = entries.filter { calendar.isDate($0.occurredAt, inSameDayAs: day) }
            .sorted { $0.occurredAt > $1.occurredAt }
        if let entry = matches.first {
            filter = DiaryFilter(day: day)
            selectedEntryID = entry.id
        } else {
            let now = Date()
            let time = calendar.dateComponents([.hour, .minute, .second], from: now)
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
            _ = createEntry(occurredAt: calendar.date(from: components) ?? day)
            filter = DiaryFilter(day: day)
        }
        viewMode = .timeline
    }

    func clearFilters() {
        filter = DiaryFilter()
        searchText = ""
    }

    func thumbnailData(for attachment: DiaryAttachment) async -> Data? {
        try? await attachmentStore.loadThumbnail(attachment: attachment)
    }

    func attachmentData(for attachment: DiaryAttachment) async -> Data? {
        try? await attachmentStore.load(attachment: attachment)
    }

    @discardableResult
    func flush() async -> Bool {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        while !dirtyEntryIDs.isEmpty {
            guard await saveDirtyEntries(ids: dirtyEntryIDs) else { return false }
        }
        return true
    }

    @discardableResult
    func completeEditingSession(id: UUID) async -> Bool {
        let shouldPresentFeedback = feedbackPendingEntryIDs.remove(id) != nil
        let didSave = await flush()
        guard didSave else {
            if shouldPresentFeedback { feedbackPendingEntryIDs.insert(id) }
            return false
        }
        if shouldPresentFeedback,
           let entry = entries.first(where: { $0.id == id }),
           entry.hasPersistableContent {
            onEntryCompleted?()
        }
        return true
    }

    @discardableResult
    func completeCurrentEditingSession() async -> Bool {
        guard let selectedEntryID else { return await flush() }
        return await completeEditingSession(id: selectedEntryID)
    }

    func exportMarkdown(to url: URL, entries: [DiaryEntry]) async throws -> URL {
        try await exportService.exportMarkdown(entries: entries, to: url)
    }

    func exportJSON(to url: URL, entries: [DiaryEntry]) async throws -> URL {
        try await exportService.exportJSON(entries: entries, to: url)
    }

    func exportZIP(to url: URL, entries: [DiaryEntry]) async throws -> URL {
        try await exportService.exportZIP(entries: entries, to: url)
    }

    func backup(to url: URL) async throws -> URL {
        guard await flush() else { throw DiaryFeatureError.unsavedChanges }
        return try await exportService.backup(to: url)
    }

    func createBackupNow() async throws -> URL {
        guard let autoBackupService else { throw DiaryFeatureError.backupUnavailable }
        guard await flush() else { throw DiaryFeatureError.unsavedChanges }
        isBackupWorking = true
        defer { isBackupWorking = false }
        let result = try await autoBackupService.backupNow()
        backupStatus = result.1
        return result.0
    }

    func refreshBackupStatus() async {
        guard let autoBackupService else {
            backupStatus = .empty
            return
        }
        backupStatus = (try? await autoBackupService.status()) ?? .empty
    }

    func restoreBackup(from url: URL) async throws {
        guard await flush() else { throw DiaryFeatureError.unsavedChanges }
        let report = try await exportService.restore(from: url)
        applyLoadReport(report)
        recentlyDeletedItems = (try? await repository.recentlyDeleted()) ?? []
    }

    private func loadFromDisk() async {
        loadState = .loading
        do {
            let report = try await repository.loadAll()
            applyLoadReport(report)
            recentlyDeletedItems = try await repository.recentlyDeleted()
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            try? await repository.purgeRecentlyDeleted(olderThan: cutoff)
            recentlyDeletedItems = try await repository.recentlyDeleted()
            loadState = .loaded
            await refreshBackupStatus()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func applyLoadReport(_ report: DiaryLoadReport) {
        var seen = Set<UUID>()
        entries = report.entries.sorted(by: { $0.updatedAt > $1.updatedAt })
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.occurredAt > $1.occurredAt }
        recoveredFiles = report.recoveredFiles
        dirtyEntryIDs.removeAll()
        dirtyEntryRevisions.removeAll()
        feedbackPendingEntryIDs.removeAll()
        selectedEntryID = entries.first?.id
    }

    private func markDirty(_ id: UUID, schedule: Bool = true) {
        dirtyEntryRevisions[id, default: 0] &+= 1
        dirtyEntryIDs.insert(id)
        feedbackPendingEntryIDs.insert(id)
        if schedule { scheduleAutoSave() }
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            _ = await self.saveDirtyEntries(ids: self.dirtyEntryIDs)
        }
    }

    private func scheduleSearchUpdate() {
        searchTask?.cancel()
        let value = searchText
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.debouncedSearchText = value
            self?.objectWillChange.send()
        }
    }

    private func saveDirtyEntries(ids: Set<UUID>) async -> Bool {
        guard !ids.isEmpty else {
            if case .saving = saveState { saveState = .idle }
            return true
        }
        let revisions = Dictionary(uniqueKeysWithValues: ids.map { ($0, dirtyEntryRevisions[$0] ?? 0) })
        let candidates = entries.filter { ids.contains($0.id) && $0.hasPersistableContent }
        let skipped = ids.subtracting(candidates.map(\.id))
        clearDirtyEntries(skipped, matching: revisions)
        guard !candidates.isEmpty else { return true }
        saveState = .saving
        let report = await repository.save(candidates)
        clearDirtyEntries(report.savedIDs, matching: revisions)
        if report.succeeded {
            saveState = .saved(Date())
            scheduleAutomaticBackup()
            return true
        }
        saveState = .failed(report.failures.map { $0.message }.joined(separator: "\n"))
        return false
    }

    private func clearDirtyEntries(_ ids: Set<UUID>, matching revisions: [UUID: UInt64]) {
        for id in ids where dirtyEntryRevisions[id] == revisions[id] {
            dirtyEntryIDs.remove(id)
            dirtyEntryRevisions[id] = nil
        }
    }

    private func scheduleAutomaticBackup() {
        guard autoBackupTask == nil, let autoBackupService else { return }
        autoBackupTask = Task { [weak self] in
            guard let self else { return }
            do {
                backupStatus = try await autoBackupService.backupIfNeeded()
            } catch {
                operationError = "自动备份失败：\(error.localizedDescription)"
            }
            autoBackupTask = nil
        }
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix(while: { $0 == "#" })
            let value = String(trimmed.prefix(30))
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
            result.append(value)
            if result.count == 20 { break }
        }
        return result
    }

    private func normalizedLocationName(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }
}

private extension DiaryEntry {
    var hasPersistableContent: Bool {
        hasContent || mood != nil || locationName?.isEmpty == false || !attachments.isEmpty || isFavorite
    }
}

enum DiaryFeatureError: LocalizedError {
    case unsavedChanges
    case backupUnavailable

    var errorDescription: String? {
        switch self {
        case .unsavedChanges: "仍有未保存的日记，操作已取消"
        case .backupUnavailable: "当前无法使用日记备份"
        }
    }
}
