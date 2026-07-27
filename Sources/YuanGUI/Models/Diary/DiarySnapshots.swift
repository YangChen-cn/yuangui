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
    case sweet    // 🥰 甜蜜
    case touched  // 🥹 感动
    case playful  // 😜 俏皮
    case missing  // 🫶 想念
    case tired    // 😴 疲惫
    case surprised // 😮 惊喜
    case confused // 😕 困惑
    case wronged  // 🥺 委屈

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
        case .sweet: "🥰"
        case .touched: "🥹"
        case .playful: "😜"
        case .missing: "🫶"
        case .tired: "😴"
        case .surprised: "😮"
        case .confused: "😕"
        case .wronged: "🥺"
        }
    }

    var title: String {
        switch self {
        case .happy: AppLocalizer.string("开心")
        case .love: AppLocalizer.string("恋爱")
        case .calm: AppLocalizer.string("平静")
        case .sad: AppLocalizer.string("难过")
        case .angry: AppLocalizer.string("生气")
        case .anxious: AppLocalizer.string("焦虑")
        case .excited: AppLocalizer.string("兴奋")
        case .neutral: AppLocalizer.string("一般")
        case .sweet: AppLocalizer.string("甜蜜")
        case .touched: AppLocalizer.string("感动")
        case .playful: AppLocalizer.string("俏皮")
        case .missing: AppLocalizer.string("想念")
        case .tired: AppLocalizer.string("疲惫")
        case .surprised: AppLocalizer.string("惊喜")
        case .confused: AppLocalizer.string("困惑")
        case .wronged: AppLocalizer.string("委屈")
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
