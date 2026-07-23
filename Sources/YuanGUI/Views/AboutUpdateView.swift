import AppKit
import SwiftUI

struct AboutUpdateView: View {
    @StateObject private var updater = AppUpdateStore()
    @Environment(\.appActions) private var appActions

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
                    VStack(alignment: .leading, spacing: 14) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                statusView
                                Spacer(minLength: 12)
                                updateActions
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                statusView
                                updateActions
                            }
                        }

                        if let release = updater.latestRelease {
                            Divider()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(release.name ?? "版本 \(release.version)")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Text("v\(release.version)")
                                        .font(.caption.monospaced().weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                    Link("在 GitHub 查看", destination: release.pageURL)
                                        .font(.caption)
                                }
                            }
                            releaseNotes(release.body)
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
        .onAppear {
            updater.setTerminationHandler(appActions.terminateForUpdate)
        }
    }

    private var updateActions: some View {
        HStack(spacing: 8) {
            Button("检查更新") { updater.check() }
                .disabled(updater.isBusy)
            if updater.state == .available {
                Button("一键更新到 \(updater.latestRelease?.version ?? "新版本")") {
                    updater.installLatest()
                }
                .buttonStyle(.borderedProminent)
            }
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseNotes(_ body: String) -> some View {
        let rows = ReleaseNoteRow.parse(body)
        return VStack(alignment: .leading, spacing: 9) {
            Text("更新说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                switch row.kind {
                case .heading:
                    Text(renderedInlineMarkdown(row.text))
                        .font(.callout.weight(.semibold))
                        .padding(.top, row.id == rows.first?.id ? 0 : 3)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.blue)
                        Text(renderedInlineMarkdown(row.text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .paragraph:
                    Text(renderedInlineMarkdown(row.text))
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func renderedInlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }
}

struct ReleaseNoteRow: Identifiable {
    enum Kind: Equatable { case heading, bullet, paragraph }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ body: String) -> [ReleaseNoteRow] {
        let source = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return [ReleaseNoteRow(id: 0, kind: .paragraph, text: "此 Release 没有填写更新日志。")]
        }
        return source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { index, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { return nil }
                if line.hasPrefix("#") {
                    return ReleaseNoteRow(
                        id: index,
                        kind: .heading,
                        text: line.drop(while: { $0 == "#" || $0.isWhitespace }).description
                    )
                }
                for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
                    return ReleaseNoteRow(id: index, kind: .bullet, text: String(line.dropFirst(marker.count)))
                }
                if let separator = line.firstIndex(of: "."),
                   line[..<separator].allSatisfy(\.isNumber),
                   line.index(after: separator) < line.endIndex,
                   line[line.index(after: separator)].isWhitespace {
                    return ReleaseNoteRow(
                        id: index,
                        kind: .bullet,
                        text: String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                    )
                }
                return ReleaseNoteRow(id: index, kind: .paragraph, text: line)
            }
    }
}

private struct AboutReleaseNoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            configuration.icon.foregroundStyle(.green)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}
