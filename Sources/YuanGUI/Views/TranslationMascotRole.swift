import SwiftUI

enum TranslationMascotRole {
    case source
    case translation

    var accent: Color {
        switch self {
        case .source: Color(red: 0.25, green: 0.58, blue: 0.94)
        case .translation: Color(red: 0.57, green: 0.45, blue: 0.88)
        }
    }

    var mode: PetMode {
        switch self {
        case .source: .yuanGui
        case .translation: .vcc
        }
    }

    var title: String {
        switch self {
        case .source: AppLocalizer.string("translation.source.roleTitle")
        case .translation: AppLocalizer.string("translation.result.roleTitle")
        }
    }
}
