import Foundation

enum PetMode: Int, CaseIterable, Identifiable {
    case yuanGui
    case vcc
    case duo

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .yuanGui: return "元圭"
        case .vcc: return "VCC"
        case .duo: return "一起"
        }
    }

    var resourceFolder: String {
        switch self {
        case .yuanGui: return "YuanGui"
        case .vcc: return "VCC"
        case .duo: return "Duo"
        }
    }

    var actions: [PetAction] {
        switch self {
        case .yuanGui:
            return [
                .init(file: "01-idle", label: "陪着你"),
                .init(file: "02-wave", label: "嗨～"),
                .init(file: "03-curious", label: "在想什么？"),
                .init(file: "04-hop", label: "好耶！"),
                .init(file: "05-read", label: "安静读会儿书"),
                .init(file: "06-system-meter", label: "系统状态交给我"),
                .init(file: "07-yawn", label: "该休息一下啦"),
                .init(file: "08-finger-heart", label: "给你一颗心")
            ]
        case .vcc:
            return [
                .init(file: "01-loaf-idle", label: "VCC 正在监工"),
                .init(file: "02-paw-wave", label: "喵～"),
                .init(file: "03-curious", label: "这是什么？"),
                .init(file: "04-pounce", label: "扑！"),
                .init(file: "05-belly-roll", label: "今天也很圆"),
                .init(file: "06-groom", label: "整理一下毛毛"),
                .init(file: "07-sleep", label: "呼噜呼噜……"),
                .init(file: "08-alert", label: "VCC 已上线")
            ]
        case .duo:
            return [
                .init(file: "01-idle", label: "我们都在这里"),
                .init(file: "02-pet", label: "摸摸 VCC"),
                .init(file: "03-cuddle", label: "抱紧这只猫"),
                .init(file: "04-wave", label: "一起打招呼"),
                .init(file: "05-read", label: "陪你安静一会儿"),
                .init(file: "06-play", label: "抓到帽绳啦"),
                .init(file: "07-alert", label: "发生什么了？"),
                .init(file: "08-hug", label: "今天也要开心")
            ]
        }
    }
}

struct PetAction: Identifiable, Hashable {
    let file: String
    let label: String
    var id: String { file }
}

enum SmartPetState: String, Equatable {
    case normal
    case lowBattery
    case memoryPressure
    case charging
    case rainy
    case bedtime

    var isUrgent: Bool {
        self == .lowBattery || self == .memoryPressure
    }

    var showsAutomaticBubble: Bool {
        isUrgent || self == .rainy || self == .bedtime
    }

    static func resolve(from snapshot: SystemSnapshot) -> SmartPetState {
        let calendar = Calendar.current
        let noon = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12))!
        return resolve(system: snapshot, weather: nil, date: noon, calendar: calendar)
    }

    static func resolve(
        system snapshot: SystemSnapshot,
        weather: WeatherSnapshot?,
        date: Date,
        calendar: Calendar = .current
    ) -> SmartPetState {
        resolveAll(system: snapshot, weather: weather, date: date, calendar: calendar).first ?? .normal
    }

    static func resolveAll(
        system snapshot: SystemSnapshot,
        weather: WeatherSnapshot?,
        date: Date,
        calendar: Calendar = .current,
        bedtimeEnabled: Bool = true,
        bedtimeStartMinutes: Int = 23 * 60,
        bedtimeEndMinutes: Int = 5 * 60
    ) -> [SmartPetState] {
        var states: [SmartPetState] = []
        if let memory = snapshot.memory,
           memory.pressure == .critical || memory.fractionUsed >= 0.90 {
            states.append(.memoryPressure)
        }
        if let battery = snapshot.battery,
           battery.isPresent,
           !battery.isCharging,
           (battery.chargeFraction ?? 1) <= 0.20 {
            states.append(.lowBattery)
        }
        if let memory = snapshot.memory,
           (memory.pressure == .warning || memory.fractionUsed >= 0.82),
           !states.contains(.memoryPressure) {
            states.append(.memoryPressure)
        }
        if weather?.isRainy == true {
            states.append(.rainy)
        }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let start = min(max(bedtimeStartMinutes, 0), 1_439)
        let end = min(max(bedtimeEndMinutes, 0), 1_439)
        let isBedtime = start < end
            ? (start..<end).contains(currentMinutes)
            : (start > end && (currentMinutes >= start || currentMinutes < end))
        if bedtimeEnabled && isBedtime {
            states.append(.bedtime)
        }
        if snapshot.battery?.isCharging == true {
            states.append(.charging)
        }
        return states
    }
}

extension PetMode {
    var chatAction: PetAction {
        PetAction(file: "14-chatting", label: "正在和你聊天")
    }

    func smartAction(for state: SmartPetState) -> PetAction? {
        switch state {
        case .normal: return nil
        case .lowBattery: return PetAction(file: "09-low-battery", label: "电量快不够啦")
        case .memoryPressure: return PetAction(file: "10-memory-pressure", label: "内存有点挤")
        case .charging: return PetAction(file: "11-charging", label: "正在补充能量")
        case .rainy: return PetAction(file: "12-rainy", label: "下雨啦，记得带伞")
        case .bedtime: return PetAction(file: "13-bedtime", label: "夜深了，该睡觉啦")
        }
    }
}
