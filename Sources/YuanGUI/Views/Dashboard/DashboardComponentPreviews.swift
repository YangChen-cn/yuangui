#if DEBUG
import SwiftUI

private let previewTrack = MusicTrack(
    id: "preview-current",
    source: .bilibili,
    title: "夏夜与晚风",
    artist: "元圭与 VCC",
    album: nil,
    coverURL: nil,
    duration: 238,
    bilibili: nil,
    subtitleURL: nil
)

#Preview("正常状态") {
    DashboardPreviewFrame {
        DashboardMetricTile(
            title: "CPU",
            systemImage: "cpu",
            primaryValue: "24%",
            detail: "用户 16%",
            status: "正常",
            severity: .normal,
            history: [0.12, 0.18, 0.15, 0.24],
            fixedMaximum: 1
        )
    }
}

#Preview("天气正常") {
    DashboardPreviewFrame {
        DashboardWeatherSummaryContent(
            presentation: .init(
                icon: "sun.max.fill",
                primaryText: "29°",
                conditionText: "晴朗 · 体感 31°",
                detailText: "湿度 70% · 风速 8 km/h",
                metadataText: "杭州市 · 15:20 更新",
                showsLocationSettings: false,
                isRefreshing: false
            ),
            onRefresh: {},
            onOpenLocationSettings: {}
        )
    }
}

#Preview("定位被拒绝") {
    DashboardPreviewFrame {
        DashboardWeatherSummaryContent(
            presentation: .resolve(snapshot: nil, status: .locationDenied, locationName: nil),
            onRefresh: {},
            onOpenLocationSettings: {}
        )
    }
}

#Preview("高 CPU 与内存紧张") {
    DashboardPreviewFrame {
        HStack {
            DashboardMetricTile(
                title: "CPU",
                systemImage: "cpu",
                primaryValue: "94%",
                detail: "用户 72%",
                status: "负载较高",
                severity: .warning,
                history: [0.4, 0.7, 0.83, 0.94],
                fixedMaximum: 1
            )
            DashboardMetricTile(
                title: "内存",
                systemImage: "memorychip",
                primaryValue: "92%",
                detail: "14.7 GB / 16 GB",
                status: "紧张",
                severity: .critical,
                history: [0.68, 0.78, 0.88, 0.92],
                fixedMaximum: 1
            )
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("低电量、充电与无电池") {
    DashboardPreviewFrame {
        VStack {
            Label("12% · 使用电池 · 约0小时42分", systemImage: "battery.25percent")
                .foregroundStyle(.orange)
            Label("82% · 充电中 · 约0小时35分", systemImage: "battery.100percent.bolt")
                .foregroundStyle(.green)
            Label("交流电源", systemImage: "powerplug.fill")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

#Preview("无音乐") {
    DashboardPreviewFrame {
        DashboardEmptyState(
            title: "暂无播放内容",
            systemImage: "music.note",
            description: "连接 Music App 后可在这里快速控制。"
        )
    }
}

#Preview("正在播放与队列") {
    DashboardPreviewFrame {
        VStack {
            DashboardQueueRow(track: previewTrack, isPlaying: true, onPlay: {})
            Toggle("其他应用播放声音时自动暂停", isOn: .constant(true))
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

#Preview("发现更新与更新失败") {
    DashboardPreviewFrame {
        VStack(spacing: 1) {
            DashboardCompactActionLabel(
                title: "检查更新",
                subtitle: "发现 2.6.0",
                systemImage: "arrow.down.circle.fill",
                role: .system
            )
            DashboardCompactActionLabel(
                title: "检查更新",
                subtitle: "网络连接失败",
                systemImage: "exclamationmark.triangle.fill",
                role: .maintenance
            )
        }
    }
    .frame(width: DashboardDesign.minimumWidth)
}

private struct DashboardPreviewFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DashboardDesign.outerPadding)
            .frame(width: DashboardDesign.preferredWidth)
            .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }
}
#endif
