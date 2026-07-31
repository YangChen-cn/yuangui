import SwiftUI

struct DashboardUpdateView: View {
    @ObservedObject var updater: AppUpdateStore
    @State private var showsPopover = false

    var body: some View {
        Button(action: presentUpdate) {
            DashboardCompactActionLabel(
                title: "检查更新",
                subtitle: subtitle,
                systemImage: systemImage,
                role: actionRole
            )
        }
        .buttonStyle(.plain)
        .disabled(updater.state == .downloading || updater.state == .installing)
        .help(help)
        .popover(isPresented: $showsPopover, arrowEdge: .leading) {
            popover
        }
    }

    private func presentUpdate() {
        showsPopover = true
        if !updater.isBusy && updater.state != .available {
            updater.check()
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .idle: AppLocalizer.string("尚未检查")
        case .checking: AppLocalizer.string("正在检查…")
        case .upToDate: AppLocalizer.string("当前已是最新版")
        case .available: "\(AppLocalizer.string("发现")) \(updater.latestUpdate?.version ?? AppLocalizer.string("新版本"))"
        case .downloading: AppLocalizer.string("正在下载…")
        case .installing: AppLocalizer.string("正在安装…")
        case .failed: AppLocalizer.string("失败，点按查看")
        }
    }

    private var systemImage: String {
        switch updater.state {
        case .idle: "arrow.triangle.2.circlepath"
        case .checking, .downloading, .installing: "progress.indicator"
        case .upToDate: "checkmark.circle.fill"
        case .available: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var actionRole: DashboardActionRole {
        if case .failed = updater.state { return .maintenance }
        return .system
    }

    private var help: String {
        if case .failed(let message) = updater.state { return "\(AppLocalizer.string("更新失败"))：\(message)" }
        return subtitle
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YuanGUI 更新")
                .font(.headline)
            Label(help, systemImage: systemImage)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("重新检查", action: updater.check)
                    .disabled(updater.isBusy)
                if updater.state == .available {
                    Button("更新到 \(updater.latestUpdate?.version ?? "新版本")", action: updater.installLatest)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private var statusColor: Color {
        switch updater.state {
        case .failed: .orange
        case .available: .accentColor
        case .upToDate: .green
        default: .secondary
        }
    }
}
