import AppKit
import SwiftUI

struct AboutUpdateView: View {
    @ObservedObject var updater: AppUpdateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPageHeader(
                    title: AppLocalizer.string("关于"),
                    subtitle: AppLocalizer.string("版本信息、更新内容与应用更新"),
                    systemImage: "info.circle.fill",
                    accent: .blue
                )
                HStack(spacing: 14) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalizer.string("元圭与 VCC"))
                            .font(.title2.bold())
                        Text(AppLocalizer.format("about.version", AppVersionInfo.version, AppVersionInfo.build))
                            .foregroundStyle(.secondary)
                        Link(AppLocalizer.string("GitHub 项目主页"), destination: URL(string: "https://github.com/YangChen-cn/yuangui")!)
                            .font(.caption)
                    }
                }

                GroupBox(AppLocalizer.string("此版本更新内容")) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(AppVersionInfo.currentReleaseHighlights, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle.fill")
                                .labelStyle(AboutReleaseNoteLabelStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox(AppLocalizer.string("update.source.preference")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding(
                            get: { updater.updateSourcePreference },
                            set: { updater.setUpdateSourcePreference($0) }
                        )) {
                            ForEach(UpdateSourcePreference.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .disabled(updater.isBusy)
                        Text(AppLocalizer.string("update.source.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox(AppLocalizer.string("检查更新")) {
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

                        if let update = updater.latestUpdate {
                            Divider()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(AppLocalizer.format("about.version.short", update.version))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Text("v\(update.version)")
                                        .font(.caption.monospaced().weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                    if let releasePageURL = update.releasePageURL {
                                        Link(AppLocalizer.string("在 GitHub 查看"), destination: releasePageURL)
                                            .font(.caption)
                                    }
                                }
                            }
                            releaseNotes(updater.latestUpdateNotes ?? update.localizedHighlights.map { "- \($0)" }.joined(separator: "\n"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox(AppLocalizer.string("about.legal")) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(AppLocalizer.string("about.license"))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AppLocalizer.string("about.notice"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("GPL-3.0-only") { openLegalDocument("LICENSE") }
                            Button("Asset license") { openLegalDocument("ASSET_LICENSE", extension: "md") }
                            Button("Third-party notices") { openLegalDocument("THIRD_PARTY_NOTICES", extension: "md") }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                Text(AppLocalizer.string("update.installDescription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
    }

    private var updateActions: some View {
        HStack(spacing: 8) {
            Button(AppLocalizer.string("检查更新")) { updater.check() }
                .disabled(updater.isBusy)
            if updater.state == .available {
                Button(AppLocalizer.format("about.updateTo", updater.latestUpdate?.version ?? AppLocalizer.string("新版本"))) {
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
            Label(AppLocalizer.string("尚未检查"), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView().controlSize(.small); Text(AppLocalizer.string("update.checking")) }
        case .upToDate:
            Label(AppLocalizer.string("当前已是最新版本"), systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .available:
            Label(AppLocalizer.format("about.releaseAvailable", updater.latestUpdate?.version ?? ""), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .downloading:
            downloadProgressView
        case .installing:
            HStack { ProgressView().controlSize(.small); Text(AppLocalizer.string("正在准备安装，应用即将重启…")) }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var downloadProgressView: some View {
        if let progress = updater.downloadProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppLocalizer.format(
                        "update.downloading.from",
                        progress.provider.displayName
                    ))
                    Spacer(minLength: 12)
                    if let fraction = progress.fractionCompleted {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                // A nil value renders an indeterminate bar: when the total
                // size is unknown the received count still shows.
                ProgressView(value: progress.fractionCompleted)
                    .progressViewStyle(.linear)
                if let totalBytes = progress.totalBytes, totalBytes > 0 {
                    Text(AppLocalizer.format(
                        "update.downloading.bytes",
                        Self.byteCount(progress.displayReceivedBytes),
                        Self.byteCount(totalBytes)
                    ))
                } else {
                    Text(AppLocalizer.format(
                        "update.downloading.received",
                        Self.byteCount(progress.displayReceivedBytes)
                    ))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progressAccessibilityLabel(progress))
        } else {
            HStack { ProgressView().controlSize(.small); Text(AppLocalizer.string("正在下载 DMG…")) }
        }
    }

    /// One combined label so VoiceOver announces source, percentage, and
    /// bytes together instead of separate unlabeled elements.
    private func progressAccessibilityLabel(_ progress: UpdateDownloadProgress) -> String {
        let source = AppLocalizer.format("update.downloading.from", progress.provider.displayName)
        let bytes: String
        if let totalBytes = progress.totalBytes, totalBytes > 0 {
            bytes = AppLocalizer.format(
                "update.downloading.bytes",
                Self.byteCount(progress.displayReceivedBytes),
                Self.byteCount(totalBytes)
            )
        } else {
            bytes = AppLocalizer.format(
                "update.downloading.received",
                Self.byteCount(progress.displayReceivedBytes)
            )
        }
        if let fraction = progress.fractionCompleted {
            return "\(source), \(Int((fraction * 100).rounded()))%, \(bytes)"
        }
        return "\(source), \(bytes)"
    }

    private static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func releaseNotes(_ body: String) -> some View {
        let rows = ReleaseNoteRow.parse(body)
        return VStack(alignment: .leading, spacing: 9) {
            Text(AppLocalizer.string("更新说明"))
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

    private func openLegalDocument(_ name: String, extension fileExtension: String? = nil) {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Legal") else { return }
        NSWorkspace.shared.open(url)
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
            return [ReleaseNoteRow(id: 0, kind: .paragraph, text: AppLocalizer.string("此 Release 没有填写更新日志。"))]
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
