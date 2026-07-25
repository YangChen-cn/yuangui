import SwiftUI

enum DashboardDesign {
    static let preferredWidth: CGFloat = 420
    static let preferredHeight: CGFloat = 520
    static let minimumWidth: CGFloat = 390
    static let minimumHeight: CGFloat = 460
    static let outerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let sectionRadius: CGFloat = 14
    static let controlRadius: CGFloat = 9
    static let rowHeight: CGFloat = 40
    static let queueLimit = 4
    static let animationDuration = 0.18

    static func accent(for style: DashboardStyle) -> Color {
        switch style {
        case .softGlass: .accentColor
        case .sakura: .pink
        case .mint: .mint
        case .midnight: .indigo
        }
    }

    static func atmosphere(for style: DashboardStyle) -> Color {
        switch style {
        case .softGlass: .secondary.opacity(0.025)
        case .sakura: .pink.opacity(0.055)
        case .mint: .mint.opacity(0.055)
        case .midnight: .indigo.opacity(0.10)
        }
    }
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
        case .normal: .init(title: "状态正常", systemImage: "checkmark.circle.fill", severity: .normal)
        case .lowBattery: .init(title: "低电量", systemImage: "battery.25percent", severity: .warning)
        case .memoryPressure: .init(title: "内存紧张", systemImage: "memorychip.fill", severity: .critical)
        case .charging: .init(title: "充电中", systemImage: "bolt.fill", severity: .normal)
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
        case .normal: .green
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
