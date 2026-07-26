import Foundation

enum PetEdgeMessageResolver {
    static func alert(
        for mode: PetMode,
        state: SmartPetState,
        snapshot: SystemSnapshot
    ) -> String {
        switch (mode, state) {
        case (.yuanGui, .lowBattery):
            return "电量有点低，记得及时充电哦～"
        case (.vcc, .lowBattery):
            return "喵！电量快见底啦。"
        case (.duo, .lowBattery):
            return "电量告急，快接上电源！"
        case (.yuanGui, .memoryPressure):
            return "内存有点挤，让 Mac 休息一下吧～"
        case (.vcc, .memoryPressure):
            return "内存挤成猫饼了，喵。"
        case (.duo, .memoryPressure):
            return "内存有点紧张，先缓一缓！"
        case (.yuanGui, .rainy):
            return "外面下雨啦，出门记得带伞～"
        case (.vcc, .rainy):
            return "下雨了，别淋湿尾巴。"
        case (.duo, .rainy):
            return "下雨啦，出门记得带伞！"
        case (.yuanGui, .bedtime):
            return "夜深啦，准备休息吧～"
        case (.vcc, .bedtime):
            return "该睡了，猫猫正在监督你。"
        case (.duo, .bedtime):
            return "很晚啦，该说晚安了！"
        case (_, .normal), (_, .charging):
            return PetStatusMessageResolver.message(snapshot: snapshot, smartState: state)
        }
    }
}
