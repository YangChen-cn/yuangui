import Foundation

enum PetAmbientChatter {
    static func candidates(
        mode: PetMode,
        system: SystemSnapshot,
        weather: WeatherSnapshot?,
        locationName: String? = nil
    ) -> [String] {
        var messages = idleMessages(for: mode)

        if let weather {
            messages.append(contentsOf: weatherMessages(
                for: mode,
                weather: weather,
                locationName: locationName
            ))
        }
        if let locationName, !locationName.isEmpty {
            messages.append(contentsOf: locationMessages(for: mode, locationName: locationName))
        }
        if let battery = system.battery, battery.isPresent {
            messages.append(contentsOf: batteryMessages(for: mode, battery: battery))
        }

        return messages
    }

    static func weatherAnnouncements(
        mode: PetMode,
        weather: WeatherSnapshot,
        locationName: String? = nil
    ) -> [String] {
        let place = locationName.map { "\($0)" } ?? "外面"
        let temperature = Int(weather.temperature.rounded())
        let apparent = Int(weather.apparentTemperature.rounded())

        if weather.isRainy {
            switch mode {
            case .yuanGui:
                return [
                    "天气更新啦，\(place)正在下雨。master 出门记得带伞，元圭会惦记你的～",
                    "master，\(place)有雨，路面可能会滑。元圭已经把带伞提醒放在这里啦。"
                ]
            case .vcc:
                return [
                    "喵喵喵，\(place)下雨啦！master 要带伞，VCC 今天就不去踩水坑了喵。",
                    "雨滴正在敲窗户喵，master 出门小心。VCC 负责在家看守罐头！"
                ]
            case .duo:
                return [
                    "喵喵喵，\(place)下雨啦！元圭提醒 master 带伞，VCC 保证不踩水坑～",
                    "天气播报：\(place)有雨。元圭准备伞，VCC 准备在门口等 master 回来。"
                ]
            }
        }

        if apparent >= 30 {
            switch mode {
            case .yuanGui:
                return ["master，\(place)今天体感 \(apparent)°，外面有点热。元圭提醒你多喝水、注意防晒哦～"]
            case .vcc:
                return ["喵喵喵，\(place)体感 \(apparent)°，热得 VCC 想摊成一张猫饼了！master 记得补水喵。"]
            case .duo:
                return ["喵喵喵，\(place)今天有点热，体感 \(apparent)°。元圭提醒补水，VCC 已经躺到阴凉处啦～"]
            }
        }

        if apparent <= 10 {
            switch mode {
            case .yuanGui:
                return ["master，\(place)现在只有 \(temperature)°，外面有点冷。元圭想提醒你多穿一件～"]
            case .vcc:
                return ["喵喵喵，\(place)只有 \(temperature)°，VCC 的爪爪都想缩起来了，master 要穿暖和喵！"]
            case .duo:
                return ["\(place)现在 \(temperature)°，有点冷。元圭给 master 递外套，VCC 负责提供暖呼呼的猫肚皮～"]
            }
        }

        switch mode {
        case .yuanGui:
            return [
                "天气更新啦，\(place)现在 \(temperature)°、\(weather.condition.title)。今天的天气还不错，master 出门也要照顾好自己～",
                "元圭看过天气啦：\(place)\(temperature)°，\(weather.condition.title)。愿 master 今天心情也很好。"
            ]
        case .vcc:
            return [
                "喵喵喵，今天天气不错！\(place)现在 \(temperature)°，适合晒一会儿猫猫～",
                "VCC 天气巡逻完成：\(place)\(temperature)°、\(weather.condition.title)。罐头也会是晴天味的吗？"
            ]
        case .duo:
            return [
                "喵喵喵，今天天气不错！\(place)现在 \(temperature)°、\(weather.condition.title)，元圭和 VCC 都来向 master 报到啦～",
                "天气更新完成：\(place)\(temperature)°。元圭负责播报，VCC 负责喵一声表示收到！"
            ]
        }
    }

    private static func weatherMessages(
        for mode: PetMode,
        weather: WeatherSnapshot,
        locationName: String?
    ) -> [String] {
        let temperature = Int(weather.temperature.rounded())
        let wind = Int(weather.windSpeed.rounded())
        let place = locationName ?? "当前位置"
        var messages: [String]

        switch mode {
        case .yuanGui:
            messages = ["\(place)今天 \(temperature)°、\(weather.condition.title)，风速约 \(wind) km/h。master 出门要照顾好自己哦～"]
        case .vcc:
            messages = ["喵～\(place)现在 \(temperature)°、\(weather.condition.title)。VCC 已经用胡须测过风啦！"]
        case .duo:
            messages = ["\(place)今天 \(temperature)°、\(weather.condition.title)，风速约 \(wind) km/h。元圭播报完毕，VCC 盖爪认证～"]
        }
        if weather.isRainy {
            messages.append(contentsOf: weatherAnnouncements(mode: mode, weather: weather, locationName: locationName))
        }
        return messages
    }

    private static func batteryMessages(for mode: PetMode, battery: BatteryMetrics) -> [String] {
        var messages: [String] = []
        let percent = battery.chargeFraction.map { Int(($0 * 100).rounded()) }

        if battery.isCharging {
            if let minutes = battery.timeRemainingMinutes, minutes > 0 {
                switch mode {
                case .yuanGui:
                    messages.append("MacBook 正在充电，再过约\(durationText(minutes))就满啦，元圭陪 master 等～")
                case .vcc:
                    messages.append("电量正在长大喵！再过约\(durationText(minutes))，VCC 就宣布充电仪式完成。")
                case .duo:
                    messages.append("MacBook 正在充电补充能量，再过约\(durationText(minutes))就满啦。元圭计时，VCC 监工～")
                }
            } else {
                messages.append("MacBook 正在补充能量，元圭和 VCC 也会陪 master 一起充满电～")
            }
            return messages
        }

        if let minutes = battery.timeRemainingMinutes, minutes > 0 {
            switch mode {
            case .yuanGui:
                messages.append("master，MacBook 预计还能使用约\(durationText(minutes))。元圭会帮你留意电量哦～")
            case .vcc:
                messages.append("喵喵喵，MacBook 预计还能使用约\(durationText(minutes))哦，VCC 已经记在小本本上了！")
            case .duo:
                messages.append("当前电量播报：MacBook 预计还能使用约\(durationText(minutes))。元圭提醒，VCC 喵喵确认～")
            }
        }
        if let percent, percent <= 25 {
            messages.append("master，MacBook 只剩 \(percent)% 电量啦，VCC 正叼着充电线跑来～")
        }
        return messages
    }

    private static func locationMessages(for mode: PetMode, locationName: String) -> [String] {
        switch mode {
        case .yuanGui:
            return ["原来 master 现在在\(locationName)呀。元圭又多知道了一点关于你的日常～"]
        case .vcc:
            return ["master 现在住在\(locationName)吗？VCC 只要有罐头吃，住在哪里都可以喵！"]
        case .duo:
            return ["原来当前位置是\(locationName)呀。元圭记住天气，VCC 只负责记住哪里有罐头～"]
        }
    }

    private static func idleMessages(for mode: PetMode) -> [String] {
        switch mode {
        case .yuanGui:
            return [
                "master 忙完了吗？元圭想陪你说说话～",
                "今天也辛苦啦，记得喝口水、伸个懒腰哦。",
                "元圭最喜欢认真生活的 master 了～",
                "别忘了保存刚才的工作哦，元圭会替你心疼丢掉的进度。",
                "看屏幕久了就望一望远处吧，眼睛也需要小小休息。",
                "不用一下子把所有事情做完，慢慢来，元圭一直陪着你。",
                "桌面有一点乱也没关系，说明 master 今天做了很多事呀。",
                "要不要放一首喜欢的歌？元圭想和你一起听。",
                "今天有哪件小事让 master 开心？元圭很想知道～",
                "肩膀放松一点，呼吸慢一点。你已经做得很好啦。"
            ]
        case .vcc:
            return [
                "喵～快来跟 VCC 聊聊天吧！",
                "VCC 巡逻完毕，master 今天也被好好守护着。",
                "VCC 把爪爪放在这里，等 master 来击掌～",
                "键盘检查完成，没有发现罐头，VCC 决定继续蹲守。",
                "master 的鼠标会跑，VCC 可以帮你按住它喵！",
                "工作这么久了，按照猫猫法则，现在应该休息五分钟。",
                "纸箱、阳光和罐头，VCC 今天只缺其中两个喵。",
                "喵喵喵，这是 VCC 的加油暗号，听到的人会立刻多一点好运！",
                "VCC 刚刚打了一个很小的哈欠，绝对不是在偷懒。",
                "如果 master 累了，可以借你一会儿呼噜声，不收罐头费。"
            ]
        case .duo:
            return [
                "快来跟 VCC 和元圭聊天吧，我们一直在这里呀～",
                "元圭和 VCC 最喜欢 master 了，今天也要开心哦！",
                "master 要不要休息一下？元圭负责陪伴，VCC 负责呼噜～",
                "无论今天忙不忙，元圭和 VCC 都会在桌面上陪着你。",
                "元圭说要记得喝水，VCC 说喝完可以奖励一个罐头。",
                "master 专心工作的时候，元圭安静陪着，VCC 安静到只剩呼噜声～",
                "今天也分工明确：元圭负责温柔，VCC 负责可爱，master 负责好好休息。",
                "遇到难题先别着急，元圭陪你想办法，VCC 陪你把眉头松开。",
                "桌面巡逻报告：一切正常，只发现一位有点辛苦的 master。",
                "等忙完这一小段，我们一起伸个懒腰吧，VCC 已经开始示范啦！",
                "元圭给 master 一颗小爱心，VCC 再盖一个梅花爪印。",
                "不管今天进度多少，只要认真走过，就值得元圭和 VCC 为你鼓掌～"
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
