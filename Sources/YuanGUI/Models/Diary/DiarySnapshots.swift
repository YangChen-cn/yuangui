import Foundation

// MARK: - 心情枚举

enum DiaryMood: String, Codable, CaseIterable, Sendable {
    case happy    // 😊 开心
    case love     // 💕 恋爱
    case calm     // 😌 平静
    case sad      // 😢 难过
    case angry    // 😠 生气
    case anxious  // 😰 焦虑
    case excited  // 🤩 兴奋
    case neutral  // 😐 一般

    var emoji: String {
        switch self {
        case .happy:   "😊"
        case .love:    "💕"
        case .calm:    "😌"
        case .sad:     "😢"
        case .angry:   "😠"
        case .anxious: "😰"
        case .excited: "🤩"
        case .neutral: "😐"
        }
    }

    var title: String {
        switch self {
        case .happy:   "开心"
        case .love:    "恋爱"
        case .calm:    "平静"
        case .sad:     "难过"
        case .angry:   "生气"
        case .anxious: "焦虑"
        case .excited: "兴奋"
        case .neutral: "一般"
        }
    }
}

// MARK: - 天气快照

struct DiaryWeatherSnapshot: Codable, Equatable, Hashable, Sendable {
    /// 摄氏度
    let temperature: Double
    /// 天气描述，如"晴"、"多云"
    let condition: String
    /// SF Symbol 名称
    let icon: String
    let capturedAt: Date
}

// MARK: - 音乐快照

struct DiaryMusicSnapshot: Codable, Equatable, Hashable, Sendable {
    let title: String
    let artist: String
    let capturedAt: Date

    init(title: String, artist: String, capturedAt: Date) {
        self.title = title
        self.artist = artist
        self.capturedAt = capturedAt
    }
}
