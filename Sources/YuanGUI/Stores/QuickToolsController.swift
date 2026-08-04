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

    /// Emitted from the actual execution point of a quick tool, so every entry
    /// (hotkey, menu bar, pet, dashboard, settings page) records usage the same
    /// way. Used for lightweight local feature-usage tracking.
    var onQuickToolUsed: ((QuickToolAction) -> Void)?

    /// Reports when a started capture session ends (any purpose). `true` means
    /// an image was actually captured; `false` means the user cancelled or an
    /// error was shown. Contract: a session that returned `true` from
    /// `beginRegionScreenshot`/`beginScreenshotTranslation` calls this exactly
    /// once; a session that did not start never calls it.
    var onCaptureSessionEnded: ((Bool) -> Void)?

    private var activeCaptureSessionID: UUID?
    private var captureSessionDidEnd = false

    private lazy var hotKeyManager = GlobalHotKeyManager { [weak self] action in
        self?.perform(action)
    }
    private let selectionController = CaptureSelectionController()
    private let captureService: ScreenCapturing
    private let ocrService: OCRTextRecognizing
    private let selectedTextProvider: SelectedTextProviding
    private weak var aiSettings: AISettingsStore?
    private let petTranslationEvents: PetTranslationEventHandling?
    private var screenshotEditor: ScreenshotEditorWindowController?
    private var translationEditor: TranslationEditorWindowController?
    private var translationEditorPresentationID: UUID?
    private var screenshotTranslationOverlay: ScreenshotTranslationOverlayWindowController?

    init(
        settings: QuickToolsSettingsStore? = nil,
        captureService: ScreenCapturing = ScreenCaptureService(),
        ocrService: OCRTextRecognizing = VisionOCRService(),
        selectedTextProvider: SelectedTextProviding? = nil,
        aiSettings: AISettingsStore? = nil,
        petTranslationEvents: PetTranslationEventHandling? = nil
    ) {
        self.settings = settings ?? QuickToolsSettingsStore()
        self.captureService = captureService
        self.ocrService = ocrService
        self.selectedTextProvider = selectedTextProvider ?? AccessibilitySelectedTextProvider()
        self.aiSettings = aiSettings
        self.petTranslationEvents = petTranslationEvents
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
            message = AppLocalizer.format(
                "quickTools.hotKeySaved",
                action.title,
                binding.displayText
            )
        } catch {
            message = error.localizedDescription
        }
    }

    func resetHotKey(for action: QuickToolAction) {
        updateHotKey(action.defaultHotKey, for: action)
    }

    /// Starts a region screenshot session.
    /// - Returns: `true` if a capture session really started (it will later
    ///   report exactly one `onCaptureSessionEnded`), `false` if it could not
    ///   start (already capturing, permission denied, …). A failed start never
    ///   reports an ended callback, so callers must not wait for one.
    @discardableResult
    func beginRegionScreenshot() -> Bool {
        beginCapture(for: .edit)
    }

    /// Starts a screenshot-translation session. Contract identical to
    /// `beginRegionScreenshot()`.
    @discardableResult
    func beginScreenshotTranslation() -> Bool {
        beginCapture(for: .translate)
    }

    private func beginCapture(for purpose: CapturePurpose) -> Bool {
        guard !isCapturing else { return false }
        screenshotTranslationOverlay?.close()
        if ScreenCapturePermission.state != .granted, !ScreenCapturePermission.request() {
            message = ScreenCaptureServiceError.permissionDenied.localizedDescription
            showError(
                title: AppLocalizer.string("无法开始截图"),
                message: message ?? AppLocalizer.string("请开启屏幕录制权限。"),
                openSettings: ScreenCapturePermission.openSettings
            )
            // No session started: no ended callback is sent, and the caller
            // already knows from the returned value that nothing will follow.
            return false
        }

        let sessionID = UUID()
        activeCaptureSessionID = sessionID
        captureSessionDidEnd = false
        isCapturing = true
        message = nil
        onQuickToolUsed?(purpose == .translate ? .screenshotTranslation : .regionScreenshot)
        selectionController.begin { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(selection):
                let excludedWindows = selectionController.windowNumbers
                Task { await self.capture(selection, excluding: excludedWindows, for: purpose, sessionID: sessionID) }
            case let .failure(error):
                self.endCaptureSession(false, sessionID: sessionID)
                if !(error is CancellationError) { present(error, title: AppLocalizer.string("截图失败")) }
            }
        }
        return true
    }

    private func endCaptureSession(_ completed: Bool, sessionID: UUID) {
        guard activeCaptureSessionID == sessionID, !captureSessionDidEnd else { return }
        captureSessionDidEnd = true
        activeCaptureSessionID = nil
        isCapturing = false
        onCaptureSessionEnded?(completed)
    }

    func translateSelection() {
        onQuickToolUsed?(.translateSelection)
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await selectedTextProvider.selectedText(promptForPermission: true)
                showTranslationEditor(snapshot: snapshot)
                message = nil
            } catch let error as AccessibilityTextError {
                showTranslationEditor(snapshot: manualSnapshot(text: "", source: AppLocalizer.string("手动输入")))
                if case .permissionDenied = error {
                    message = error.localizedDescription
                    showError(
                        title: AppLocalizer.string("需要辅助功能权限"),
                        message: AppLocalizer.string("quickTools.accessibilitySettingsHelp"),
                        openSettings: AccessibilityPermission.openSettings
                    )
                } else {
                    message = AppLocalizer.string("未取得选中文字，已打开手动输入翻译。")
                }
            } catch {
                present(error, title: AppLocalizer.string("无法翻译所选文字"))
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
        for purpose: CapturePurpose,
        sessionID: UUID
    ) async {
        do {
            let captured = try await TranslationPerformance.measure(.capture) {
                try await captureService.capture(selection, excludingWindowNumbers: windows)
            }
            selectionController.cancel()
            endCaptureSession(true, sessionID: sessionID)
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
                        snapshot: manualSnapshot(text: "", source: AppLocalizer.string("截图 OCR 覆盖")),
                        nonChineseTarget: settings.nonChineseTarget,
                        chineseTarget: settings.chineseTarget,
                        engine: settings.translationEngine,
                        onlineConfiguration: onlineTranslationConfiguration,
                        petEventHandler: petTranslationEvents,
                        onClose: { [weak self] in self?.screenshotTranslationOverlay = nil }
                    )
                    screenshotTranslationOverlay = controller
                    controller.show()
                    presenter = controller
                } else {
                    presenter = showTranslationEditor(
                        snapshot: manualSnapshot(text: "", source: AppLocalizer.string("截图 OCR")),
                        interactionSource: .screenshot
                    )
                }
                petTranslationEvents?.handle(.translationStarted(source: "", origin: .screenshot))
                presenter.setMessage(AppLocalizer.string("正在识别截图文字…"))
                do {
                    let recognition = try await ocrService.recognizeLayout(in: captured.image)
                    let text = recognition.text
                    presenter.updateRecognition(recognition)
                    let status = text.isEmpty
                        ? (settings.screenshotTranslationOverlayEnabled
                            ? AppLocalizer.string("未识别到文字，请关闭后重新框选。")
                            : AppLocalizer.string("未识别到文字，可以手动输入。"))
                        : nil
                    presenter.setMessage(status)
                    message = status
                    if let status {
                        petTranslationEvents?.handle(.translationFailed(
                            message: status,
                            origin: .screenshot
                        ))
                    }
                } catch {
                    presenter.setMessage(error.localizedDescription)
                    message = error.localizedDescription
                    petTranslationEvents?.handle(.translationFailed(
                        message: error.localizedDescription,
                        origin: .screenshot
                    ))
                }
            }
        } catch {
            selectionController.cancel()
            endCaptureSession(false, sessionID: sessionID)
            let openSettings: (() -> Void)?
            if let captureError = error as? ScreenCaptureServiceError, case .permissionDenied = captureError {
                openSettings = ScreenCapturePermission.openSettings
            } else {
                openSettings = nil
            }
            present(error, title: AppLocalizer.string("截图失败"), openSettings: openSettings)
        }
    }

    @discardableResult
    func showTranslationEditor(
        snapshot: TranslationTargetSnapshot,
        interactionSource: TranslationInteractionSource = .selection
    ) -> TranslationEditorWindowController {
        translationEditor?.close()
        translationEditor = nil
        let presentationID = UUID()
        translationEditorPresentationID = presentationID
        let controller = TranslationEditorWindowController(
            snapshot: snapshot,
            nonChineseTarget: settings.nonChineseTarget,
            chineseTarget: settings.chineseTarget,
            engine: settings.translationEngine,
            onlineConfiguration: onlineTranslationConfiguration,
            petEventHandler: petTranslationEvents,
            interactionSource: interactionSource,
            onClose: { [weak self] in
                guard self?.translationEditorPresentationID == presentationID else { return }
                self?.translationEditor = nil
                self?.translationEditorPresentationID = nil
            }
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
        alert.addButton(withTitle: AppLocalizer.string("知道了"))
        if openSettings != nil { alert.addButton(withTitle: AppLocalizer.string("打开系统设置")) }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { openSettings?() }
    }
}
