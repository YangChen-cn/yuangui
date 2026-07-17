import AppKit
import SwiftUI

struct AboutUpdateView: View {
    @StateObject private var updater = AppUpdateStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("元圭与 VCC")
                            .font(.title2.bold())
                        Text("版本 \(AppVersionInfo.version)（\(AppVersionInfo.build)）")
                            .foregroundStyle(.secondary)
                        Link("GitHub 项目主页", destination: URL(string: "https://github.com/YangChen-cn/yuangui")!)
                            .font(.caption)
                    }
                }

                GroupBox("此版本更新内容") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(AppVersionInfo.currentReleaseHighlights, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle.fill")
                                .labelStyle(AboutReleaseNoteLabelStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("检查更新") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            statusView
                            Spacer()
                            Button("检查更新") { updater.check() }
                                .disabled(updater.isBusy)
                            if updater.state == .available {
                                Button("一键更新到 \(updater.latestRelease?.version ?? "新版本")") {
                                    updater.installLatest()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let release = updater.latestRelease {
                            Divider()
                            HStack {
                                Text(release.name ?? "版本 \(release.version)")
                                    .font(.headline)
                                Spacer()
                                Link("在 GitHub 查看", destination: release.pageURL)
                                    .font(.caption)
                            }
                            Text(renderedReleaseNotes(release.body))
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                Text("更新会从 GitHub Release 下载 DMG，校验应用标识、版本号和代码签名后自动替换当前应用并重新打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.state {
        case .idle:
            Label("尚未检查", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("正在读取 GitHub Release…") }
        case .upToDate:
            Label("当前已是最新版本", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .available:
            Label("发现版本 \(updater.latestRelease?.version ?? "")", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .downloading:
            HStack { ProgressView().controlSize(.small); Text("正在下载 DMG…") }
        case .installing:
            HStack { ProgressView().controlSize(.small); Text("正在准备安装，应用即将重启…") }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    private func renderedReleaseNotes(_ body: String) -> AttributedString {
        let source = body.isEmpty ? "此 Release 没有填写更新日志。" : body
        return (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }
}

private struct AboutReleaseNoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            configuration.icon.foregroundStyle(.green)
            configuration.title
        }
        .font(.callout)
    }
}
