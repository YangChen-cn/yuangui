import AppKit
import ApplicationServices
import Foundation

@MainActor
final class QuickToolsController: ObservableObject {
    private enum CapturePurpose {
        case edit
        case translate
    }

    let settings: QuickToolsSettingsStore
    @Published private(set) var message: String?
    @Published private(set) var isCapturing = false

    private lazy var hotKeyManager = GlobalHotKeyManager { [weak self] action in
        self?.perform(action)
    }
    private let selectionController = CaptureSelectionController()
    private let captureService: ScreenCapturing
    private let ocrService: OCRTextRecognizing
    private let selectedTextProvider: SelectedTextProviding
    private weak var aiSettings: AISettingsStore?
    private var screenshotEditor: ScreenshotEditorWindowController?
    private var translationEditor: TranslationEditorWindowController?
    private var screenshotTranslationOverlay: ScreenshotTranslationOverlayWindowController?

    init(
        settings: QuickToolsSettingsStore? = nil,
        captureService: ScreenCapturing = ScreenCaptureService(),
        ocrService: OCRTextRecognizing = VisionOCRService(),
        selectedTextProvider: SelectedTextProviding? = nil,
        aiSettings: AISettingsStore? = nil
    ) {
        self.settings = settings ?? QuickToolsSettingsStore()
        self.captureService = captureService
        self.ocrService = ocrService
        self.selectedTextProvider = selectedTextProvider ?? AccessibilitySelectedTextProvider()
        self.aiSettings = aiSettings
    }

    func start() {
        do {
            try hotKeyManager.start(bindings: [
                .regionScreenshot: settings.screenshotHotKey,
                .screenshotTranslation: settings.screenshotTranslationHotKey,
                .translateSelection: settings.translationHotKey
            ])
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func stop() {
        hotKeyManager.stop()
        selectionController.cancel()
    }

    func perform(_ action: QuickToolAction) {
        switch action {
        case .regionScreenshot: beginRegionScreenshot()
        case .screenshotTranslation: beginScreenshotTranslation()
        case .translateSelection: translateSelection()
        }
    }

    func updateHotKey(_ binding: HotKeyBinding, for action: QuickToolAction) {
        let otherBindings = QuickToolAction.allCases
            .filter { $0 != action }
            .map(settings.hotKey(for:))
        do {
            try hotKeyManager.update(binding, for: action, otherBindings: otherBindings)
            settings.saveHotKey(binding, for: action)
            message = "已设置\(action.title)快捷键：\(binding.displayText)"
        } catch {
            message = error.localizedDescription
        }
    }

    func resetHotKey(for action: QuickToolAction) {
        updateHotKey(action.defaultHotKey, for: action)
    }

    func beginRegionScreenshot() {
        beginCapture(for: .edit)
    }

    func beginScreenshotTranslation() {
        beginCapture(for: .translate)
    }

    private func beginCapture(for purpose: CapturePurpose) {
        guard !isCapturing else { return }
        screenshotTranslationOverlay?.close()
        if ScreenCapturePermission.state != .granted, !ScreenCapturePermission.request() {
            message = ScreenCaptureServiceError.permissionDenied.localizedDescription
            showError(title: "无法开始截图", message: message ?? "请开启屏幕录制权限。", openSettings: ScreenCapturePermission.openSettings)
            return
        }

        isCapturing = true
        message = nil
        selectionController.begin { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(selection):
                let excludedWindows = selectionController.windowNumbers
                Task { await self.capture(selection, excluding: excludedWindows, for: purpose) }
            case let .failure(error):
                isCapturing = false
                selectionController.cancel()
                if !(error is CancellationError) { present(error, title: "截图失败") }
            }
        }
    }

    func translateSelection() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await selectedTextProvider.selectedText(promptForPermission: true)
                showTranslationEditor(snapshot: snapshot)
                message = nil
            } catch let error as AccessibilityTextError {
                showTranslationEditor(snapshot: manualSnapshot(text: "", source: "手动输入"))
                if case .permissionDenied = error {
                    message = error.localizedDescription
                    showError(
                        title: "需要辅助功能权限",
                        message: "请在系统设置中允许 YuanGUI 控制这台 Mac。若已允许但仍无法取词，请先移除旧的 YuanGUI 项，再重新添加当前应用。",
                        openSettings: AccessibilityPermission.openSettings
                    )
                } else {
                    message = "未取得选中文字，已打开手动输入翻译。"
                }
            } catch {
                present(error, title: "无法翻译所选文字")
            }
        }
    }

    private var onlineTranslationConfiguration: AITranslationConfiguration? {
        guard let aiSettings else { return nil }
        let configuration = AITranslationConfiguration(
            baseURL: aiSettings.baseURL,
            model: aiSettings.model,
            apiKey: aiSettings.apiKey
        )
        return configuration.isUsable ? configuration : nil
    }

    private func capture(
        _ selection: ScreenshotSelection,
        excluding windows: Set<Int>,
        for purpose: CapturePurpose
    ) async {
        do {
            let captured = try await TranslationPerformance.measure(.capture) {
                try await captureService.capture(selection, excludingWindowNumbers: windows)
            }
            selectionController.cancel()
            isCapturing = false
            switch purpose {
            case .edit:
                screenshotEditor = nil
                let controller = ScreenshotEditorWindowController(
                    image: captured.image,
                    directoryPath: { [weak self] in self?.settings.screenshotDirectoryPath ?? "" },
                    onClose: { [weak self] in self?.screenshotEditor = nil }
                )
                screenshotEditor = controller
                controller.show()
            case .translate:
                let presenter: ScreenshotTranslationPresenting
                if settings.screenshotTranslationOverlayEnabled {
                    let controller = ScreenshotTranslationOverlayWindowController(
                        selection: selection,
                        image: captured.image,
                        snapshot: manualSnapshot(text: "", source: "截图 OCR 覆盖"),
                        nonChineseTarget: settings.nonChineseTarget,
                        chineseTarget: settings.chineseTarget,
                        engine: settings.translationEngine,
                        onlineConfiguration: onlineTranslationConfiguration,
                        onClose: { [weak self] in self?.screenshotTranslationOverlay = nil }
                    )
                    screenshotTranslationOverlay = controller
                    controller.show()
                    presenter = controller
                } else {
                    presenter = showTranslationEditor(snapshot: manualSnapshot(text: "", source: "截图 OCR"))
                }
                presenter.setMessage("正在识别截图文字…")
                do {
                    let recognition = try await ocrService.recognizeLayout(in: captured.image)
                    let text = recognition.text
                    presenter.updateRecognition(recognition)
                    let status = text.isEmpty
                        ? (settings.screenshotTranslationOverlayEnabled
                            ? "未识别到文字，请关闭后重新框选。"
                            : "未识别到文字，可以手动输入。")
                        : nil
                    presenter.setMessage(status)
                    message = status
                } catch {
                    presenter.setMessage(error.localizedDescription)
                    message = error.localizedDescription
                }
            }
        } catch {
            selectionController.cancel()
            isCapturing = false
            let openSettings: (() -> Void)?
            if let captureError = error as? ScreenCaptureServiceError, case .permissionDenied = captureError {
                openSettings = ScreenCapturePermission.openSettings
            } else {
                openSettings = nil
            }
            present(error, title: "截图失败", openSettings: openSettings)
        }
    }

    @discardableResult
    private func showTranslationEditor(snapshot: TranslationTargetSnapshot) -> TranslationEditorWindowController {
        translationEditor = nil
        let controller = TranslationEditorWindowController(
            snapshot: snapshot,
            nonChineseTarget: settings.nonChineseTarget,
            chineseTarget: settings.chineseTarget,
            engine: settings.translationEngine,
            onlineConfiguration: onlineTranslationConfiguration,
            onClose: { [weak self] in self?.translationEditor = nil }
        )
        translationEditor = controller
        controller.show()
        return controller
    }

    private func manualSnapshot(text: String, source: String) -> TranslationTargetSnapshot {
        TranslationTargetSnapshot(
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: source,
            element: AXUIElementCreateSystemWide(),
            originalText: text,
            fullValue: nil,
            selectedRange: nil,
            role: nil,
            canReplace: false
        )
    }

    private func present(_ error: Error, title: String, openSettings: (() -> Void)? = nil) {
        message = error.localizedDescription
        showError(title: title, message: error.localizedDescription, openSettings: openSettings)
    }

    private func showError(title: String, message: String, openSettings: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        if openSettings != nil { alert.addButton(withTitle: "打开系统设置") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { openSettings?() }
    }
}
