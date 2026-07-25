import SwiftUI

enum DashboardDesign {
    static let preferredWidth: CGFloat = 420
    static let preferredHeight: CGFloat = 540
    static let minimumWidth: CGFloat = 390
    static let minimumHeight: CGFloat = 460
    static let outerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 10
    static let compactSpacing: CGFloat = 8
    static let sectionRadius: CGFloat = 14
    static let controlRadius: CGFloat = 9
    static let rowHeight: CGFloat = 36
    static let queueLimit = 4
    static let animationDuration = 0.18
    static let heroRadius: CGFloat = 16
    static let avatarSize: CGFloat = 46

    static func palette(for style: DashboardStyle) -> DashboardPalette {
        switch style {
        case .softGlass:
            DashboardPalette(
                accent: .blue,
                topGlow: Color(red: 1.0, green: 0.72, blue: 0.52),
                bottomGlow: Color(red: 0.48, green: 0.71, blue: 1.0),
                ambientOpacity: 0.11,
                preferredColorScheme: nil
            )
        case .sakura:
            DashboardPalette(
                accent: Color(red: 0.88, green: 0.36, blue: 0.52),
                topGlow: Color(red: 1.0, green: 0.55, blue: 0.68),
                bottomGlow: Color(red: 0.96, green: 0.73, blue: 0.55),
                ambientOpacity: 0.14,
                preferredColorScheme: nil
            )
        case .mint:
            DashboardPalette(
                accent: Color(red: 0.12, green: 0.60, blue: 0.49),
                topGlow: Color(red: 0.35, green: 0.83, blue: 0.68),
                bottomGlow: Color(red: 0.36, green: 0.66, blue: 0.82),
                ambientOpacity: 0.12,
                preferredColorScheme: nil
            )
        case .midnight:
            DashboardPalette(
                accent: Color(red: 0.56, green: 0.62, blue: 1.0),
                topGlow: Color(red: 0.46, green: 0.30, blue: 0.86),
                bottomGlow: Color(red: 0.20, green: 0.46, blue: 0.82),
                ambientOpacity: 0.20,
                preferredColorScheme: .dark
            )
        }
    }
}

struct DashboardPalette {
    let accent: Color
    let topGlow: Color
    let bottomGlow: Color
    let ambientOpacity: Double
    let preferredColorScheme: ColorScheme?
}

enum DashboardToolIdentifier: String, CaseIterable {
    case chat
    case diary
    case regionScreenshot
    case screenshotTranslation
    case translateSelection
    case cleanup
    case uninstall
    case update
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case music
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .music: "音乐"
        case .tools: "工具"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .music: "music.note"
        case .tools: "square.grid.2x2"
        }
    }

    func adjacent(_ direction: MoveCommandDirection) -> DashboardSection {
        guard let index = Self.allCases.firstIndex(of: self) else { return self }
        switch direction {
        case .left:
            return Self.allCases[max(index - 1, Self.allCases.startIndex)]
        case .right:
            return Self.allCases[min(index + 1, Self.allCases.index(before: Self.allCases.endIndex))]
        default:
            return self
        }
    }
}

struct DashboardSmartStatePresentation: Equatable {
    let title: String
    let systemImage: String
    let severity: DashboardStatusSeverity

    static func resolve(_ state: SmartPetState) -> Self {
        switch state {
        case .normal: .init(title: "一切平稳", systemImage: "checkmark.circle", severity: .normal)
        case .lowBattery: .init(title: "低电量", systemImage: "battery.25percent", severity: .warning)
        case .memoryPressure: .init(title: "内存紧张", systemImage: "memorychip.fill", severity: .critical)
        case .charging: .init(title: "充电中", systemImage: "bolt.fill", severity: .informational)
        case .rainy: .init(title: "下雨了", systemImage: "umbrella.fill", severity: .informational)
        case .bedtime: .init(title: "该休息了", systemImage: "moon.zzz.fill", severity: .informational)
        }
    }
}

enum DashboardStatusSeverity: Equatable {
    case normal
    case informational
    case warning
    case critical

    var color: Color {
        switch self {
        case .normal: .secondary
        case .informational: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}

enum DashboardPanelLayout {
    static let screenInset: CGFloat = 8

    static func size(in visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(DashboardDesign.preferredWidth, max(visibleFrame.width - screenInset * 2, 0)),
            height: min(DashboardDesign.preferredHeight, max(visibleFrame.height - screenInset * 2, 0))
        )
    }
}
