import Foundation

enum PetAmbientChatter {
    static func candidates(
        mode: PetMode,
        system: SystemSnapshot,
        weather: WeatherSnapshot?
    ) -> [String] {
        var messages: [String] = []

        if let weather {
            let temperature = Int(weather.temperature.rounded())
            let wind = Int(weather.windSpeed.rounded())
            messages.append(
                "今天 \(temperature)°，是\(weather.condition.title)，风速约 \(wind) km/h，master 出门要照顾好自己哦～"
            )
            if weather.isRainy {
                messages.append("外面正在下雨，元圭把伞准备好啦，VCC 也不可以踩水坑哦～")
            }
        }

        if let battery = system.battery, battery.isPresent {
            let percent = battery.chargeFraction.map { Int(($0 * 100).rounded()) }
            if !battery.isCharging, let percent, percent <= 25 {
                messages.append("master，Mac 只剩 \(percent)% 电量啦，VCC 正叼着充电线跑来～")
            } else if battery.isCharging {
                if let minutes = battery.timeRemainingMinutes, minutes > 0 {
                    messages.append("正在乖乖充电，再过约\(durationText(minutes))就满啦，元圭陪 master 等～")
                } else {
                    messages.append("Mac 正在补充能量，元圭和 VCC 也会陪 master 一起充满电～")
                }
            }
        }

        messages.append(contentsOf: idleMessages(for: mode))
        return messages
    }

    private static func idleMessages(for mode: PetMode) -> [String] {
        switch mode {
        case .yuanGui:
            return [
                "master 忙完了吗？元圭想陪你说说话～",
                "今天也辛苦啦，记得喝口水、伸个懒腰哦。",
                "元圭最喜欢认真生活的 master 了～"
            ]
        case .vcc:
            return [
                "喵～快来跟 VCC 聊聊天吧！",
                "VCC 巡逻完毕，master 今天也被好好守护着。",
                "VCC 把爪爪放在这里，等 master 来击掌～"
            ]
        case .duo:
            return [
                "快来跟 VCC 和元圭聊天吧，我们一直在这里呀～",
                "元圭和 VCC 最喜欢 master 了，今天也要开心哦！",
                "master 要不要休息一下？元圭负责陪伴，VCC 负责呼噜～",
                "无论今天忙不忙，元圭和 VCC 都会在桌面上陪着你。"
            ]
        }
    }

    private static func durationText(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours)小时\(minutes)分钟" }
        if hours > 0 { return "\(hours)小时" }
        return "\(minutes)分钟"
    }
}
