import Foundation

enum DashboardHeaderPresentation {
    static func greeting(
        at date: Date,
        calendar: Calendar = .current
    ) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: AppLocalizer.string("早上好")
        case 11..<14: AppLocalizer.string("中午好")
        case 14..<18: AppLocalizer.string("下午好")
        case 18..<23: AppLocalizer.string("晚上好")
        default: AppLocalizer.string("夜深了")
        }
    }

    static func companionTitle(for mode: PetMode) -> String {
        switch mode {
        case .yuanGui: AppLocalizer.string("元圭在这里")
        case .vcc: AppLocalizer.string("VCC 正在陪你")
        case .duo: AppLocalizer.string("元圭和 VCC 都在")
        }
    }
}
