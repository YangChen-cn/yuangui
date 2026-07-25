import Foundation

enum DashboardHeaderPresentation {
    static func greeting(
        at date: Date,
        calendar: Calendar = .current
    ) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        case 18..<23: "晚上好"
        default: "夜深了"
        }
    }

    static func companionTitle(for mode: PetMode) -> String {
        switch mode {
        case .yuanGui: "元圭在这里"
        case .vcc: "VCC 正在陪你"
        case .duo: "元圭和 VCC 都在"
        }
    }
}
