import Foundation

enum DashboardStyle: Int, CaseIterable, Identifiable {
    case softGlass
    case sakura
    case mint
    case midnight

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .softGlass: return "柔光"
        case .sakura: return "樱花"
        case .mint: return "薄荷"
        case .midnight: return "夜色"
        }
    }
}
