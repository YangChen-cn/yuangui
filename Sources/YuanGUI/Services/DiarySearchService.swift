import Foundation

/// 日记搜索与过滤服务（无状态，纯函数）
struct DiarySearchService: Sendable {

    /// 全文搜索（标题 + 正文 + 标签）
    func search(query: String, in entries: [DiaryEntry]) -> [DiaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let lowercased = trimmed.lowercased()
        return entries.filter { entry in
            (entry.title?.lowercased().contains(lowercased) ?? false)
                || entry.body.lowercased().contains(lowercased)
                || entry.tags.contains(where: { $0.lowercased().contains(lowercased) })
        }
    }

    /// 按日期范围过滤（闭区间）
    func filter(entries: [DiaryEntry], from: Date, to: Date) -> [DiaryEntry] {
        entries.filter { $0.occurredAt >= from && $0.occurredAt <= to }
    }

    /// 按标签过滤
    func filter(entries: [DiaryEntry], tag: String) -> [DiaryEntry] {
        let lowercased = tag.lowercased()
        return entries.filter { entry in
            entry.tags.contains(where: { $0.lowercased() == lowercased })
        }
    }

    /// 按心情过滤
    func filter(entries: [DiaryEntry], mood: DiaryMood) -> [DiaryEntry] {
        entries.filter { $0.mood == mood }
    }

    /// 仅收藏
    func favorites(in entries: [DiaryEntry]) -> [DiaryEntry] {
        entries.filter(\.isFavorite)
    }

    /// 组合查询
    func query(_ filter: DiaryQueryFilter, in entries: [DiaryEntry]) -> [DiaryEntry] {
        var result = entries
        if let text = filter.text, !text.isEmpty {
            result = search(query: text, in: result)
        }
        if let tag = filter.tag {
            result = self.filter(entries: result, tag: tag)
        }
        if let mood = filter.mood {
            result = self.filter(entries: result, mood: mood)
        }
        if let from = filter.from, let to = filter.to {
            result = self.filter(entries: result, from: from, to: to)
        }
        if filter.favoritesOnly {
            result = favorites(in: result)
        }
        return result
    }
}

/// 组合查询条件
struct DiaryQueryFilter: Sendable {
    var text: String?
    var tag: String?
    var mood: DiaryMood?
    var from: Date?
    var to: Date?
    var favoritesOnly: Bool = false
}
