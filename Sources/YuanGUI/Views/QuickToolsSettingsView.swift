import AppKit
import SwiftUI

struct QuickToolsSettingsView: View {
    @ObservedObject var controller: QuickToolsController
    @ObservedObject var settings: QuickToolsSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: AppLocalizer.string("快捷工具"),
                subtitle: AppLocalizer.string("集中管理截图、截图翻译和划词翻译"),
                systemImage: "wand.and.stars",
                accent: .blue
            )
            Form {
            Section(AppLocalizer.string("全局快捷键")) {
                shortcutRow(.regionScreenshot, binding: settings.screenshotHotKey)
                shortcutRow(.screenshotTranslation, binding: settings.screenshotTranslationHotKey)
                shortcutRow(.translateSelection, binding: settings.translationHotKey)
                Text(AppLocalizer.string("点击快捷键框后录制新组合；Esc 取消录制。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(AppLocalizer.string("区域截图")) {
                LabeledContent(AppLocalizer.string("保存文件夹")) {
                    HStack {
                        Text(settings.screenshotDirectoryPath)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .trailing)
                        Button(AppLocalizer.string("选择…"), action: chooseScreenshotDirectory)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalizer.string(
                        ScreenCapturePermission.state == .granted
                            ? "屏幕录制权限已开启"
                            : "尚未开启屏幕录制权限"
                    ))
                    if ScreenCapturePermission.state != .granted {
                        HStack(spacing: 8) {
                            permissionButton("请求权限") { _ = ScreenCapturePermission.request() }
                            permissionButton("系统设置", action: ScreenCapturePermission.openSettings)
                        }
                    }
                    HStack(spacing: 8) {
                        actionButton("开始截图") { controller.beginRegionScreenshot() }
                        actionButton("截图翻译") { controller.beginScreenshotTranslation() }
                    }
                }
                Toggle(AppLocalizer.string("将截图译文覆盖显示在原位置"), isOn: Binding(
                    get: { settings.screenshotTranslationOverlayEnabled },
                    set: settings.setScreenshotTranslationOverlayEnabled
                ))
                Text(AppLocalizer.string("开启后不再打开截图翻译窗口，而是在框选区域上显示可拖动的译文覆盖层；仍可复制或关闭。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppLocalizer.string("划词翻译")) {
                Picker(AppLocalizer.string("翻译引擎"), selection: Binding(
                    get: { settings.translationEngine },
                    set: settings.setTranslationEngine
                )) {
                    ForEach(TranslationEngine.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Text(AppLocalizer.format(
                        "quickTools.defaultShortcut",
                        SystemShortcutTranslationService.shortcutName
                    ))
                    Spacer()
                    Button(AppLocalizer.string("获取快捷指令")) {
                        if let url = SystemShortcutTranslationService.installURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .disabled(SystemShortcutTranslationService.installURL == nil)
                }
                Picker(AppLocalizer.string("非中文默认翻译为"), selection: Binding(
                    get: { settings.nonChineseTarget },
                    set: settings.setNonChineseTarget
                )) {
                    ForEach(QuickToolLanguage.allCases) { Text($0.title).tag($0) }
                }
                Picker(AppLocalizer.string("中文默认翻译为"), selection: Binding(
                    get: { settings.chineseTarget },
                    set: settings.setChineseTarget
                )) {
                    ForEach(QuickToolLanguage.allCases.filter { $0 != .simplifiedChinese }) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalizer.string(
                        AccessibilityPermission.isGranted
                            ? "辅助功能权限已开启"
                            : "尚未开启辅助功能权限"
                    ))
                    if !AccessibilityPermission.isGranted {
                        HStack(spacing: 8) {
                            permissionButton("请求权限") { _ = AccessibilityPermission.request() }
                            permissionButton("系统设置", action: AccessibilityPermission.openSettings)
                        }
                    }
                }
                Text(AppLocalizer.string("划词后按快捷键；没有选中文字时会打开手动输入窗口。原文可修正并重新翻译，也可复制译文或安全替换可编辑的原选区。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(AppLocalizer.string("截图翻译使用 Vision 在本机 OCR。翻译默认通过系统快捷指令免费调用 Apple 翻译；在线 AI 仅在你明确选择时使用。网页与截图等只读来源支持编辑、翻译和复制，但不能替换原文。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let message = controller.message {
                Section { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func shortcutRow(_ action: QuickToolAction, binding: HotKeyBinding) -> some View {
        HStack {
            Label(action.title, systemImage: action.systemImage)
            Spacer()
            ShortcutRecorderView(binding: binding) { controller.updateHotKey($0, for: action) }
                .frame(width: 126, height: 28)
            Button(AppLocalizer.string("恢复默认")) { controller.resetHotKey(for: action) }
        }
    }

    private func permissionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(AppLocalizer.string(title), action: action)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(AppLocalizer.string(title), action: action)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func chooseScreenshotDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppLocalizer.string("选择")
        panel.directoryURL = URL(fileURLWithPath: settings.screenshotDirectoryPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url { settings.setScreenshotDirectory(url) }
    }
}

private extension QuickToolAction {
    var systemImage: String {
        switch self {
        case .regionScreenshot: "scissors"
        case .screenshotTranslation: "viewfinder.circle"
        case .translateSelection: "translate"
        }
    }
}
