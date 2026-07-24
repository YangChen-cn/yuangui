import Combine
import Foundation

/// 日记功能主 Store
@MainActor
final class DiaryFeature: ObservableObject {
    // MARK: - Published State

    @Published var entries: [DiaryEntry] = []
    @Published var selectedEntryID: DiaryEntry.ID?
    @Published var searchText: String = ""
    @Published var activeTag: String?
    @Published var showFavoritesOnly: Bool = false
    @Published var isDirty: Bool = false

    // MARK: - Dependencies

    private let repository: DiaryRepository
    private let attachmentStore: DiaryAttachmentStore
    private let searchService: DiarySearchService
    private weak var weatherService: WeatherService?
    private weak var musicFeature: MusicFeature?

    /// 保存成功回调（桌宠反馈用）
    var onSaved: (() -> Void)?

    // MARK: - Auto-save

    private var autoSaveTask: Task<Void, Never>?

    // MARK: - View Mode

    enum ViewMode: String, CaseIterable, Identifiable {
        case timeline = "时间线"
        case calendar = "日历"
        case photoWall = "照片墙"
        case onThisDay = "那年今日"
        var id: String { rawValue }
    }

    @Published var viewMode: ViewMode = .timeline

    // MARK: - Init

    init(
        repository: DiaryRepository,
        attachmentStore: DiaryAttachmentStore,
        searchService: DiarySearchService,
        weatherService: WeatherService? = nil,
        musicFeature: MusicFeature? = nil
    ) {
        self.repository = repository
        self.attachmentStore = attachmentStore
        self.searchService = searchService
        self.weatherService = weatherService
        self.musicFeature = musicFeature
    }

    /// 便利初始化：使用默认存储路径
    convenience init(weatherService: WeatherService? = nil, musicFeature: MusicFeature? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseURL = appSupport.appendingPathComponent("YuanGUI/Diary", isDirectory: true)
        self.init(
            repository: DiaryRepository(baseURL: baseURL),
            attachmentStore: DiaryAttachmentStore(baseURL: baseURL),
            searchService: DiarySearchService(),
            weatherService: weatherService,
            musicFeature: musicFeature
        )
    }

    // MARK: - CRUD

    /// 创建新日记（自动捕获天气和音乐快照）
    func createEntry(occurredAt: Date = Date()) -> DiaryEntry {
        var entry = DiaryEntry(occurredAt: occurredAt)

        // 自动捕获天气快照（仅在温度合理时记录）
        if let weather = weatherService?.snapshot, weather.temperature > -50, weather.temperature < 60 {
            entry.weather = DiaryWeatherSnapshot(
                temperature: weather.temperature,
                condition: weather.condition.title,
                icon: weather.condition.symbol,
                capturedAt: Date()
            )
        }

        // 自动捕获音乐快照（仅在有歌曲信息时记录）
        if let track = musicFeature?.playback.currentTrack, !track.title.isEmpty {
            entry.music = DiaryMusicSnapshot(
                title: track.title,
                artist: track.artist,
                albumArt: nil,
                capturedAt: Date()
            )
        }

        entries.insert(entry, at: 0)
        selectedEntryID = entry.id
        scheduleAutoSave()
        return entry
    }

    /// 更新日记（触发自动保存）
    func updateEntry(_ entry: DiaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.updatedAt = Date()
        entries[index] = updated
        isDirty = true
        scheduleAutoSave()
    }

    /// 删除日记
    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        if selectedEntryID == id {
            selectedEntryID = entries.first?.id
        }
        // 同步删除文件，避免重新打开时文件仍存在被重新加载
        do {
            try repository.delete(id: id)
        } catch {
            print("[DiaryFeature] 删除文件失败 \(id): \(error)")
        }
        cleanupAttachments()
    }

    /// 切换收藏
    func toggleFavorite(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isFavorite.toggle()
        entries[index].updatedAt = Date()
        isDirty = true
        scheduleAutoSave()
    }

    // MARK: - Attachments

    /// 添加附件
    func addAttachment(to entryID: UUID, imageData: Data, name: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let attachment = try attachmentStore.saveImage(data: imageData, originalName: name)
        entries[index].attachments.append(attachment)
        entries[index].updatedAt = Date()
        isDirty = true
        scheduleAutoSave()
    }

    /// 移除附件
    func removeAttachment(from entryID: UUID, attachmentID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].attachments.removeAll { $0.id == attachmentID }
        entries[index].updatedAt = Date()
        isDirty = true
        scheduleAutoSave()
    }

    // MARK: - Computed Properties

    /// 过滤后的日记列表
    var filteredEntries: [DiaryEntry] {
        var result = entries
        if !searchText.isEmpty {
            result = searchService.search(query: searchText, in: result)
        }
        if let tag = activeTag {
            result = searchService.filter(entries: result, tag: tag)
        }
        if showFavoritesOnly {
            result = searchService.favorites(in: result)
        }
        return result.sorted { $0.occurredAt > $1.occurredAt }
    }

    /// 那年今日
    var onThisDayEntries: [DiaryEntry] {
        (try? repository.entriesForOnThisDay()) ?? []
    }

    /// 所有已用标签（去重排序）
    var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            for tag in entry.tags {
                let lower = tag.lowercased()
                if seen.insert(lower).inserted {
                    result.append(tag)
                }
            }
        }
        return result.sorted()
    }

    // MARK: - Persistence

    /// 从磁盘加载
    func loadFromDisk() {
        do {
            let loaded = try repository.loadAll()
            // 去重：同一 ID 保留较新的条目
            var seen = Set<UUID>()
            var unique: [DiaryEntry] = []
            for entry in loaded.sorted(by: { $0.updatedAt > $1.updatedAt }) {
                if seen.insert(entry.id).inserted {
                    unique.append(entry)
                }
            }
            entries = unique.sorted { $0.occurredAt > $1.occurredAt }
        } catch {
            print("[DiaryFeature] 加载失败: \(error)")
        }
    }

    /// 立即保存所有脏数据
    func flush() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        saveDirtyEntries()
    }

    // MARK: - Private

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒防抖
            guard !Task.isCancelled, let self else { return }
            self.saveDirtyEntries()
        }
    }

    private func saveDirtyEntries() {
        var saved = false
        for entry in entries where entry.hasContent {
            do {
                try repository.save(entry)
                saved = true
            } catch {
                print("[DiaryFeature] 保存失败 \(entry.id): \(error)")
            }
        }
        isDirty = false
        if saved {
            onSaved?()
        }
    }

    // MARK: - Export

    /// 获取导出服务
    func exportService() -> DiaryExportService {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseURL = appSupport.appendingPathComponent("YuanGUI/Diary", isDirectory: true)
        return DiaryExportService(
            repository: DiaryRepository(baseURL: baseURL),
            attachmentStore: DiaryAttachmentStore(baseURL: baseURL)
        )
    }

    private func cleanupAttachments() {
        let usedFilenames = Set(entries.flatMap { $0.attachments.map(\.filename) })
        try? attachmentStore.cleanup(usedFilenames: usedFilenames)
    }
}
