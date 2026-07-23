import Foundation

enum PetStatusMessageResolver {
    static func message(snapshot: SystemSnapshot, smartState: SmartPetState) -> String {
        switch smartState {
        case .lowBattery:
            let value = snapshot.battery?.chargeFraction.map(MetricFormatting.percent) ?? "很低"
            return "电量只剩 \(value)，快接上电源吧～"
        case .memoryPressure:
            let value = snapshot.memory.map { MetricFormatting.percent($0.fractionUsed) }
            return value.map { "现在内存占用有些高（\($0)），要不要休息一下？" }
                ?? "现在内存占用有些高，要不要休息一下？"
        case .charging:
            return "抱紧充电器，能量恢复中！"
        case .rainy:
            return "下雨啦，出门要记得带伞哦～"
        case .bedtime:
            return "夜深了，快和我们一起睡觉吧～"
        case .normal:
            return normalMessage(for: snapshot)
        }
    }

    private static func normalMessage(for snapshot: SystemSnapshot) -> String {
        if let battery = snapshot.battery,
           battery.isPresent,
           !battery.isCharging,
           (battery.chargeFraction ?? 1) <= 0.20 {
            let value = battery.chargeFraction.map(MetricFormatting.percent) ?? "很低"
            return "现在电量有些低（\(value)），记得及时充电哦～"
        }

        if let memory = snapshot.memory,
           memory.pressure == .critical || memory.fractionUsed >= 0.90 {
            return "现在内存占用有些高（\(MetricFormatting.percent(memory.fractionUsed))），我在帮你看着～"
        }

        if let cpu = snapshot.cpu, cpu.total >= 0.80 {
            return "CPU 现在有点忙（\(MetricFormatting.percent(cpu.total))），让 Mac 喘口气吧～"
        }

        if snapshot.battery?.isCharging == true {
            return "正在充电，能量一点点回来啦～"
        }

        return "Mac 状态不错，我会帮你看着～"
    }
}
