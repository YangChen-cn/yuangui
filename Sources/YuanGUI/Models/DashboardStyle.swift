import Foundation

enum DashboardStyle: Int, CaseIterable, Identifiable {
    case softGlass
    case sakura
    case mint
    case midnight
    case liquidGlass

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .softGlass: return AppLocalizer.string("柔光")
        case .sakura: return AppLocalizer.string("樱花")
        case .mint: return AppLocalizer.string("薄荷")
        case .midnight: return AppLocalizer.string("夜色")
        case .liquidGlass: return AppLocalizer.string("液态玻璃")
        }
    }
}
