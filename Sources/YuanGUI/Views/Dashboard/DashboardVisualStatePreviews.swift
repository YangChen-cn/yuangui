#if DEBUG
import SwiftUI

#Preview("概览页 · Liquid Glass · 浅色") {
    DashboardStaticPreviewShell(section: .overview) {
        DashboardWeatherSummaryContent(
            presentation: .init(
                icon: "sun.max.fill",
                primaryText: "29°",
                conditionText: "晴朗 · 体感 31°",
                detailText: "湿度 70% · 风速 8 km/h",
                metadataText: "绍兴市 · 15:20 更新",
                showsLocationSettings: false,
                isRefreshing: false
            ),
            onRefresh: {},
            onOpenLocationSettings: {}
        )
        HStack {
            DashboardMetricTile(
                title: "CPU",
                systemImage: "cpu",
                primaryValue: "24%",
                detail: "用户 16%",
                status: "",
                severity: .normal,
                history: [0.12, 0.18, 0.15, 0.24],
                fixedMaximum: 1
            )
            DashboardMetricTile(
                title: "内存",
                systemImage: "memorychip",
                primaryValue: "68%",
                detail: "10.9 GB / 16 GB",
                status: "",
                severity: .normal,
                history: [0.62, 0.64, 0.67, 0.68],
                fixedMaximum: 1
            )
        }
        DashboardSectionSurface(prominence: .subtle) {
            Label("磁盘 248 GB 可用 · 网络 ↓ 4.2 MB/s", systemImage: "internaldrive")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("概览页 · Liquid Glass · 深色") {
    DashboardStaticPreviewShell(section: .overview) {
        DashboardSectionSurface(prominence: .hero) {
            Label("雨天 · 元圭和 VCC 都在", systemImage: "cloud.rain.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack {
            DashboardMetricTile(
                title: "CPU",
                systemImage: "cpu",
                primaryValue: "76%",
                detail: "负载较高",
                status: "注意",
                severity: .warning,
                history: [0.45, 0.58, 0.71, 0.76],
                fixedMaximum: 1
            )
            DashboardMetricTile(
                title: "内存",
                systemImage: "memorychip",
                primaryValue: "91%",
                detail: "14.6 GB / 16 GB",
                status: "紧张",
                severity: .critical,
                history: [0.74, 0.82, 0.88, 0.91],
                fixedMaximum: 1
            )
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("音乐页 · 固定数据") {
    DashboardStaticPreviewShell(section: .music) {
        DashboardSectionSurface(prominence: .hero) {
            HStack(spacing: 12) {
                MusicArtworkView(track: dashboardPreviewTrack, size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dashboardPreviewTrack.title)
                        .font(.headline)
                    Text(dashboardPreviewTrack.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("哔哩哔哩", systemImage: "play.tv")
                        .font(.caption)
                }
                Spacer()
                Button("播放", systemImage: "play.fill", action: {})
                    .labelStyle(.iconOnly)
                    .dashboardSystemGlassButton(isProminent: true)
            }
        }
        VStack(spacing: 1) {
            DashboardQueueRow(track: dashboardPreviewQueue[0], isPlaying: false, onPlay: {})
            DashboardQueueRow(track: dashboardPreviewQueue[1], isPlaying: false, onPlay: {})
            DashboardQueueRow(track: dashboardPreviewQueue[2], isPlaying: false, onPlay: {})
        }
    }
}

#Preview("工具页 · 固定数据") {
    DashboardStaticPreviewShell(section: .tools) {
        DashboardSectionSurface(prominence: .hero) {
            HStack {
                Label("AI 对话", systemImage: "bubble.left.and.bubble.right")
                Spacer()
                Label("手帐本", systemImage: "book.closed")
            }
            .frame(maxWidth: .infinity)
        }
        DashboardSectionSurface(prominence: .subtle) {
            VStack(alignment: .leading, spacing: 8) {
                Label("划词翻译", systemImage: "character.book.closed")
                Label("清理屋", systemImage: "sparkles")
                Label("设置", systemImage: "gearshape")
                Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("番茄钟运行") {
    DashboardPreviewControlStrip {
        DashboardFocusButton(title: "18:42", isRunning: true, action: {})
    }
}

#Preview("Footer 开关选中状态") {
    DashboardPreviewControlStrip {
        DashboardToggleButton(
            title: "桌宠显示",
            systemImage: "pawprint.fill",
            isOn: true,
            action: {}
        )
        DashboardToggleButton(
            title: "迷你状态",
            systemImage: "gauge.with.dots.needle.0percent",
            isOn: false,
            action: {}
        )
    }
}

private let dashboardPreviewTrack = MusicTrack(
    id: "liquid-preview-current",
    source: .bilibili,
    title: "夏夜与晚风",
    artist: "元圭与 VCC",
    album: nil,
    coverURL: nil,
    duration: 238,
    bilibili: nil,
    subtitleURL: nil
)

private let dashboardPreviewQueue = (1...3).map { index in
    MusicTrack(
        id: "liquid-preview-\(index)",
        source: .bilibili,
        title: "接下来播放 \(index)",
        artist: "固定预览歌手",
        album: nil,
        coverURL: nil,
        duration: TimeInterval(180 + index * 12),
        bilibili: nil,
        subtitleURL: nil
    )
}

private struct DashboardStaticPreviewShell<Content: View>: View {
    let section: DashboardSection
    @ViewBuilder let content: Content

    private let palette = DashboardDesign.palette(for: .liquidGlass)

    var body: some View {
        VStack(spacing: DashboardDesign.sectionSpacing) {
            HStack {
                DashboardPetAvatarView(mode: .duo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("下午好")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("元圭和 VCC 都在")
                        .font(.headline)
                        .bold()
                }
                Spacer()
                DashboardFocusButton(title: "番茄钟", isRunning: false, action: {})
            }
            DashboardSectionPicker(selection: .constant(section))
            VStack(spacing: DashboardDesign.compactSpacing) {
                content
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                DashboardToggleButton(
                    title: "桌宠显示",
                    systemImage: "pawprint.fill",
                    isOn: true,
                    action: {}
                )
                DashboardToggleButton(
                    title: "迷你状态",
                    systemImage: "gauge.with.dots.needle.0percent",
                    isOn: false,
                    action: {}
                )
                Spacer()
                Menu("更多", systemImage: "ellipsis.circle") {}
                    .menuStyle(.borderlessButton)
            }
        }
        .padding(DashboardDesign.outerPadding)
        .frame(
            width: DashboardDesign.preferredWidth,
            height: DashboardDesign.preferredHeight(for: section)
        )
        .background {
            DashboardAtmosphereBackground(
                palette: palette,
                mode: .duo,
                smartState: .normal
            )
        }
        .tint(palette.accent)
        .environment(\.dashboardVisualTreatment, palette.treatment)
    }
}

private struct DashboardPreviewControlStrip<Content: View>: View {
    @ViewBuilder let content: Content

    private let palette = DashboardDesign.palette(for: .liquidGlass)

    var body: some View {
        HStack {
            content
        }
        .padding(18)
        .background {
            DashboardAtmosphereBackground(
                palette: palette,
                mode: .duo,
                smartState: .normal
            )
        }
        .tint(palette.accent)
        .environment(\.dashboardVisualTreatment, palette.treatment)
    }
}
#endif
