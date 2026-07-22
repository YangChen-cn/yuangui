import AppKit
import Foundation
import NaturalLanguage
import Translation

@MainActor
final class TranslationEditorStore: ObservableObject {
    enum State: Equatable {
        case idle
        case translating
        case ready
        case failed(String)
        case replacing
    }

    let targetSnapshot: TranslationTargetSnapshot
    let originalSourceText: String
    let sourceApplicationName: String

    @Published var editableSourceText: String
    @Published private(set) var translatedText = ""
    @Published private(set) var translatedLines: [String] = []
    @Published private(set) var detectedSourceLanguage: String?
    @Published private(set) var targetLanguage: QuickToolLanguage
    @Published private(set) var state: State = .idle
    @Published var message: String?

    let engine: TranslationEngine
    private let replacementService: AccessibilityTextReplacing
    private let shortcutService: SystemShortcutTranslationServicing
    private let onlineService: OnlineTranslationServicing
    private let onlineConfiguration: AITranslationConfiguration?
    private let pipeline: TranslationPipeline
    private let onReplaced: () -> Void
    private let nonChineseTarget: QuickToolLanguage
    private let chineseTarget: QuickToolLanguage
    private let automaticallySwitchesTarget: Bool
    private var userSelectedTarget = false

    init(
        snapshot: TranslationTargetSnapshot,
        nonChineseTarget: QuickToolLanguage,
        chineseTarget: QuickToolLanguage,
        engine: TranslationEngine,
        onlineConfiguration: AITranslationConfiguration?,
        replacementService: AccessibilityTextReplacing? = nil,
        shortcutService: SystemShortcutTranslationServicing = SystemShortcutTranslationService(),
        onlineService: OnlineTranslationServicing = OnlineTranslationService(),
        pipeline: TranslationPipeline = .shared,
        onReplaced: @escaping () -> Void
    ) {
        targetSnapshot = snapshot
        originalSourceText = snapshot.originalText
        let formattedSource = TranslationTextFormatter.addingSemanticLineBreaks(snapshot.originalText)
        editableSourceText = formattedSource
        sourceApplicationName = snapshot.applicationName
        self.replacementService = replacementService ?? AccessibilityTextReplacementService()
        self.shortcutService = shortcutService
        self.engine = engine
        self.onlineConfiguration = onlineConfiguration
        self.onlineService = onlineService
        self.pipeline = pipeline
        self.onReplaced = onReplaced
        self.nonChineseTarget = nonChineseTarget
        self.chineseTarget = chineseTarget
        automaticallySwitchesTarget = formattedSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let dominant = NLLanguageRecognizer.dominantLanguage(for: formattedSource)?.rawValue
        detectedSourceLanguage = dominant
        targetLanguage = dominant?.hasPrefix("zh") == true ? chineseTarget : nonChineseTarget
    }

    var canReplace: Bool {
        targetSnapshot.canReplace
            && !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .replacing
    }

    var usesOnlineTranslation: Bool {
        engine == .onlineAI
    }

    var usesShortcutTranslation: Bool { engine == .systemShortcut }
    var canInstallShortcut: Bool { usesShortcutTranslation && SystemShortcutTranslationService.installURL != nil }

    var replacementHint: String {
        if sourceApplicationName.hasPrefix("手动输入") { return "手动输入模式" }
        if sourceApplicationName.hasPrefix("截图 OCR") { return "截图识别文字，仅支持复制译文" }
        return "原位置只读，仅支持复制译文"
    }

    var engineTitle: String {
        switch engine {
        case .systemShortcut: "系统快捷指令"
        case .system: "系统离线"
        case .onlineAI: "在线 AI"
        }
    }

    func requestTargetLanguage(_ language: QuickToolLanguage) {
        userSelectedTarget = true
        guard language != targetLanguage else { return }
        targetLanguage = language
        translatedText = ""
        translatedLines = []
        state = .idle
    }

    func updateEditableSourceText(_ text: String) {
        editableSourceText = text
        translatedText = ""
        translatedLines = []
        state = .idle
        guard automaticallySwitchesTarget, !userSelectedTarget else { return }
        let dominant = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
        detectedSourceLanguage = dominant
        targetLanguage = dominant?.hasPrefix("zh") == true ? chineseTarget : nonChineseTarget
    }

    func formatSourceLineBreaks() {
        let formatted = TranslationTextFormatter.addingSemanticLineBreaks(editableSourceText)
        guard formatted != editableSourceText else {
            message = "当前文本不需要重新整理。"
            return
        }
        updateEditableSourceText(formatted)
        message = "已按列表结构整理换行。"
    }

    func performTranslation(using session: TranslationSession) async {
        let requestedTarget = targetLanguage
        let requestedSource = editableSourceText
        guard !requestedSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = ""
            translatedLines = []
            state = .idle
            return
        }
        state = .translating
        message = nil
        do {
            let segment = TranslationSegment(id: "0", sourceText: requestedSource)
            let request = translationRequest(segments: [segment], target: requestedTarget)
            let results = try await pipeline.translate(request) {
                let response = try await session.translate(requestedSource)
                return [TranslationSegmentResult(
                    id: segment.id,
                    sourceText: segment.sourceText,
                    translatedText: response.targetText,
                    detectedSourceLanguage: response.sourceLanguage.minimalIdentifier
                )]
            }
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            guard let result = results.first else { throw TranslationPipelineError.emptyResult }
            detectedSourceLanguage = result.detectedSourceLanguage
            translatedText = TranslationTextFormatter.addingSemanticLineBreaks(result.translatedText)
            translatedLines = [translatedText]
            state = .ready
        } catch is CancellationError {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            state = .idle
        } catch {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            translatedLines = []
            state = .failed(error.localizedDescription)
        }
    }

    func performOnlineTranslation() async {
        let requestedTarget = targetLanguage
        let requestedSource = editableSourceText
        guard !requestedSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = ""
            translatedLines = []
            state = .idle
            return
        }
        guard let onlineConfiguration else {
            translatedText = ""
            translatedLines = []
            state = .failed(OnlineTranslationError.notConfigured.localizedDescription)
            return
        }
        state = .translating
        message = nil
        do {
            let segment = TranslationSegment(id: "0", sourceText: requestedSource)
            let request = translationRequest(segments: [segment], target: requestedTarget)
            let results = try await pipeline.translate(request) { [onlineService, onlineConfiguration] in
                let result = try await onlineService.translate(
                    requestedSource,
                    target: requestedTarget,
                    configuration: onlineConfiguration
                )
                return [TranslationSegmentResult(
                    id: segment.id,
                    sourceText: segment.sourceText,
                    translatedText: result
                )]
            }
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            guard let result = results.first else { throw TranslationPipelineError.emptyResult }
            translatedText = TranslationTextFormatter.addingSemanticLineBreaks(result.translatedText)
            translatedLines = [translatedText]
            state = .ready
        } catch is CancellationError {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            state = .idle
        } catch {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            translatedLines = []
            state = .failed(error.localizedDescription)
        }
    }

    func performShortcutTranslation() async {
        let requestedTarget = targetLanguage
        let requestedSource = editableSourceText
        guard !requestedSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = ""
            translatedLines = []
            state = .idle
            return
        }
        state = .translating
        message = nil
        do {
            let segment = TranslationSegment(id: "0", sourceText: requestedSource)
            let request = translationRequest(segments: [segment], target: requestedTarget)
            let results = try await pipeline.translate(request) { [shortcutService] in
                let result = try await shortcutService.translate(requestedSource, target: requestedTarget)
                return [TranslationSegmentResult(
                    id: segment.id,
                    sourceText: segment.sourceText,
                    translatedText: result
                )]
            }
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            guard let result = results.first else { throw TranslationPipelineError.emptyResult }
            translatedText = TranslationTextFormatter.addingSemanticLineBreaks(result.translatedText)
            translatedLines = [translatedText]
            state = .ready
        } catch is CancellationError {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            state = .idle
        } catch {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            translatedLines = []
            state = .failed(error.localizedDescription)
        }
    }

    func performLineTranslations(using session: TranslationSession, sourceLines: [String]) async {
        let requestedTarget = targetLanguage
        let requestedSource = editableSourceText
        let lines = Self.normalizedSourceLines(sourceLines)
        guard !lines.isEmpty else {
            translatedText = ""
            translatedLines = []
            state = .idle
            return
        }
        state = .translating
        message = nil
        do {
            let segments = Self.translationSegments(for: lines)
            let request = translationRequest(segments: segments, target: requestedTarget)
            let results = try await pipeline.translate(request) {
                let batch = segments.map {
                    TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.id)
                }
                var mapped: [String: TranslationSegmentResult] = [:]
                for try await response in session.translate(batch: batch) {
                    guard let identifier = response.clientIdentifier,
                          let segment = segments.first(where: { $0.id == identifier }) else { continue }
                    mapped[identifier] = TranslationSegmentResult(
                        id: identifier,
                        sourceText: segment.sourceText,
                        translatedText: response.targetText,
                        detectedSourceLanguage: response.sourceLanguage.minimalIdentifier
                    )
                }
                return segments.compactMap { mapped[$0.id] }
            }
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            guard results.count == segments.count else { throw TranslationPipelineError.incompleteResult }
            detectedSourceLanguage = results.compactMap(\.detectedSourceLanguage).first
            applyLineTranslations(results.map(\.translatedText))
        } catch is CancellationError {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            state = .idle
        } catch {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            translatedText = ""
            translatedLines = []
            state = .failed(error.localizedDescription)
        }
    }

    func performOnlineLineTranslations(sourceLines: [String]) async {
        let requestedTarget = targetLanguage
        let requestedSource = editableSourceText
        let lines = Self.normalizedSourceLines(sourceLines)
        guard !lines.isEmpty else {
            translatedText = ""
            translatedLines = []
            state = .idle
            return
        }
        guard let onlineConfiguration else {
            translatedText = ""
            translatedLines = []
            state = .failed(OnlineTranslationError.notConfigured.localizedDescription)
            return
        }
        state = .translating
        message = nil
        do {
            let segments = Self.translationSegments(for: lines)
            let request = translationRequest(segments: segments, target: requestedTarget)
            let results = try await pipeline.translate(request) { [onlineService, onlineConfiguration] in
                try await onlineService.translateSegments(
                    segments,
                    target: requestedTarget,
                    configuration: onlineConfiguration
                )
            }
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            guard results.count == segments.count else { throw TranslationPipelineError.incompleteResult }
            applyLineTranslations(results.map(\.translatedText))
        } catch is CancellationError {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            state = .idle
        } catch {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            translatedText = ""
            translatedLines = []
            state = .failed(error.localizedDescription)
        }
    }

    func performShortcutLineTranslations(sourceLines: [String]) async {
        let requestedTarget = targetLanguage
        let requestedSource = editableSourceText
        let lines = Self.normalizedSourceLines(sourceLines)
        guard !lines.isEmpty else {
            translatedText = ""
            translatedLines = []
            state = .idle
            return
        }
        state = .translating
        message = nil
        do {
            let segments = Self.translationSegments(for: lines)
            let request = translationRequest(segments: segments, target: requestedTarget)
            let results = try await pipeline.translate(request) { [shortcutService] in
                let translated = try await shortcutService.translate(
                    ScreenshotTranslationLineAligner.combinedText(for: lines),
                    target: requestedTarget
                )
                let aligned = ScreenshotTranslationLineAligner.align(translated, to: lines)
                return zip(segments, aligned).map { segment, text in
                    TranslationSegmentResult(
                        id: segment.id,
                        sourceText: segment.sourceText,
                        translatedText: text
                    )
                }
            }
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            guard results.count == segments.count else { throw TranslationPipelineError.incompleteResult }
            applyLineTranslations(results.map(\.translatedText))
        } catch is CancellationError {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            state = .idle
        } catch {
            guard targetLanguage == requestedTarget, editableSourceText == requestedSource else { return }
            translatedText = ""
            translatedLines = []
            state = .failed(error.localizedDescription)
        }
    }

    func installShortcut() {
        guard let url = SystemShortcutTranslationService.installURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyTranslation() {
        let value = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        message = "已复制译文"
    }

    func replaceOriginal() async {
        guard canReplace else {
            message = targetSnapshot.canReplace ? "请等待翻译完成。" : AccessibilityTextError.targetReadOnly.localizedDescription
            return
        }
        state = .replacing
        message = nil
        do {
            try await replacementService.replace(targetSnapshot, with: translatedText)
            onReplaced()
        } catch {
            state = .ready
            message = error.localizedDescription
        }
    }

    func clearSensitiveState() {
        editableSourceText = ""
        translatedText = ""
        translatedLines = []
        message = nil
    }

    private func applyLineTranslations(_ lines: [String]) {
        translatedLines = lines
        translatedText = lines.joined(separator: "\n")
        state = .ready
    }

    private static func normalizedSourceLines(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func translationSegments(for lines: [String]) -> [TranslationSegment] {
        lines.enumerated().map { index, text in
            TranslationSegment(id: String(index), sourceText: text)
        }
    }

    private func translationRequest(
        segments: [TranslationSegment],
        target: QuickToolLanguage
    ) -> TranslationRequest {
        let variant: String
        if engine == .onlineAI, let onlineConfiguration {
            variant = onlineConfiguration.baseURL + "\u{0}" + onlineConfiguration.model
        } else {
            variant = ""
        }
        return TranslationRequest(
            segments: segments,
            targetLanguage: target,
            engine: engine,
            configurationVariant: variant
        )
    }

}

private enum TranslationPipelineError: LocalizedError {
    case emptyResult
    case incompleteResult

    var errorDescription: String? {
        switch self {
        case .emptyResult: "翻译服务没有返回译文。"
        case .incompleteResult: "部分截图文字没有返回译文，请重试。"
        }
    }
}
