import Foundation

/// 日记条目
struct DiaryEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    /// 用户选择的发生时间
    var occurredAt: Date
    /// 首次创建时间
    var createdAt: Date
    /// 最后修改时间
    var updatedAt: Date

    /// 标题（可选，参考 Memos 的无标题模式）
    var title: String?
    /// Markdown 正文
    var body: String
    /// 心情
    var mood: DiaryMood?
    /// 标签，去重排序
    var tags: [String]

    /// 天气快照
    var weather: DiaryWeatherSnapshot?
    /// 当前播放歌曲快照
    var music: DiaryMusicSnapshot?
    /// 地点名称
    var locationName: String?

    /// 附件列表
    var attachments: [DiaryAttachment]
    /// 收藏标记
    var isFavorite: Bool

    /// 用于时间线显示的标题：有标题用标题，无标题取正文前 50 字
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 50 {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 50)
        return String(trimmed[..<index]) + "…"
    }

    /// 正文字数统计
    var wordCount: Int {
        body.count
    }

    /// 是否有实际内容（非空）
    var hasContent: Bool {
        !(title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil,
        body: String = "",
        mood: DiaryMood? = nil,
        tags: [String] = [],
        weather: DiaryWeatherSnapshot? = nil,
        music: DiaryMusicSnapshot? = nil,
        locationName: String? = nil,
        attachments: [DiaryAttachment] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.body = body
        self.mood = mood
        self.tags = tags
        self.weather = weather
        self.music = music
        self.locationName = locationName
        self.attachments = attachments
        self.isFavorite = isFavorite
    }
}
