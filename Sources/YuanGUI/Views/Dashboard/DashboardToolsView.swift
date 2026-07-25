import SwiftUI

enum DashboardActionRole {
    case yuanGUI
    case system
    case maintenance

    var color: Color {
        switch self {
        case .yuanGUI: .accentColor
        case .system: .secondary
        case .maintenance: .orange
        }
    }
}

struct DashboardToolsView: View {
    static let toolIdentifiers = DashboardToolIdentifier.allCases

    @ObservedObject var quickTools: QuickToolsController
    @ObservedObject var updater: AppUpdateStore
    let openSettings: () -> Void
    let dismiss: () -> Void

    @Environment(\.appActions) private var appActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Text("常用工具")
                    .font(.caption)
                    .bold()
                LazyVGrid(
                    columns: [.init(.flexible()), .init(.flexible())],
                    spacing: 8
                ) {
                    DashboardQuickAction(title: "AI 对话", subtitle: "和元圭、VCC 聊聊", systemImage: "message.fill", role: .yuanGUI) {
                        launch { appActions.open(.chat) }
                    }
                    DashboardQuickAction(title: "手帐本", subtitle: "记录今天的故事", systemImage: "book.closed.fill", role: .yuanGUI) {
                        launch { appActions.open(.diary) }
                    }
                    DashboardQuickAction(title: "区域截图", subtitle: quickTools.settings.screenshotHotKey.displayText, systemImage: "viewfinder", role: .system) {
                        launch(quickTools.beginRegionScreenshot)
                    }
                    DashboardQuickAction(title: "截图翻译", subtitle: quickTools.settings.screenshotTranslationHotKey.displayText, systemImage: "text.viewfinder", role: .system) {
                        launch(quickTools.beginScreenshotTranslation)
                    }
                }
                Text("更多工具")
                    .font(.caption)
                    .bold()
                    .padding(.top, 2)
                VStack(spacing: 1) {
                    compact("划词翻译", quickTools.settings.translationHotKey.displayText, "translate", .system) {
                        launch(quickTools.translateSelection)
                    }
                    compact("清理屋", "扫描缓存与残留", "sparkles", .maintenance) {
                        launch { appActions.open(.maintenance(tab: 0)) }
                    }
                    compact("软件卸载", "应用与关联残留", "shippingbox", .maintenance) {
                        launch { appActions.open(.maintenance(tab: 1)) }
                    }
                    compact("设置", "快捷键与偏好", "gearshape", .system) {
                        launch(openSettings)
                    }
                    DashboardUpdateView(updater: updater)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(.rect)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工具")
    }

    private func compact(
        _ title: String,
        _ subtitle: String,
        _ systemImage: String,
        _ role: DashboardActionRole,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DashboardCompactActionLabel(title: title, subtitle: subtitle, systemImage: systemImage, role: role)
        }
        .buttonStyle(.plain)
    }

    private func launch(_ action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

struct DashboardQuickAction: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let role: DashboardActionRole
    let action: () -> Void

    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(role.color)
                Text(title)
                    .bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .padding(9)
            .background(
                backgroundColor,
                in: .rect(cornerRadius: DashboardDesign.sectionRadius)
            )
            .contentShape(.rect(cornerRadius: DashboardDesign.sectionRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(title)，\(subtitle)")
    }

    private var backgroundColor: Color {
        switch role {
        case .yuanGUI:
            Color.accentColor.opacity(isHovering ? 0.15 : 0.10)
        case .system, .maintenance:
            Color.primary.opacity(isHovering ? 0.07 : 0.035)
        }
    }
}

struct DashboardCompactActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let role: DashboardActionRole

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(role.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 7)
        .frame(height: 37)
        .background(
            Color.primary.opacity(isHovering ? 0.065 : 0),
            in: .rect(cornerRadius: DashboardDesign.controlRadius)
        )
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
