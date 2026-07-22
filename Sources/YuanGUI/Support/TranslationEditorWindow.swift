import AppKit
import Combine
import SwiftUI

@MainActor
protocol ScreenshotTranslationPresenting: AnyObject {
    func updateSourceText(_ text: String)
    func updateRecognition(_ recognition: OCRRecognition)
    func setMessage(_ message: String?)
}

extension ScreenshotTranslationPresenting {
    func updateRecognition(_ recognition: OCRRecognition) {
        updateSourceText(recognition.text)
    }
}

struct TranslationWindowLayout: Equatable {
    let contentSize: CGSize
    let sourceHeight: CGFloat
    let resultHeight: CGFloat

    @MainActor
    static func calculate(
        source: String,
        translation: String,
        availableFrame: CGRect,
        preferredWidth: CGFloat = 440
    ) -> TranslationWindowLayout {
        let width = min(max(400, preferredWidth), max(400, availableFrame.width - 32))
        let textWidth = max(240, width - 48)
        let maximumHeight = max(300, availableFrame.height - 32)
        let fixedHeight: CGFloat = 190
        let variableBudget = max(132, maximumHeight - fixedHeight)

        let measuredSource = measuredHeight(
            source.isEmpty ? "输入要翻译的文字…" : source,
            font: .systemFont(ofSize: 13),
            width: textWidth - 12
        ) + 22
        let measuredResult = measuredHeight(
            translation.isEmpty ? "等待翻译…" : translation,
            font: .systemFont(ofSize: 15, weight: .medium),
            width: textWidth - 20
        ) + 24

        var sourceHeight = min(max(64, measuredSource), max(64, variableBudget * 0.42))
        var resultHeight = min(max(68, measuredResult), max(68, variableBudget - sourceHeight))
        let unused = variableBudget - sourceHeight - resultHeight
        if unused > 0 {
            let sourceNeed = max(0, measuredSource - sourceHeight)
            let sourceGrowth = min(unused, sourceNeed)
            sourceHeight += sourceGrowth
            resultHeight += min(unused - sourceGrowth, max(0, measuredResult - resultHeight))
        }
        if sourceHeight + resultHeight > variableBudget {
            let overflow = sourceHeight + resultHeight - variableBudget
            if resultHeight - overflow >= 68 {
                resultHeight -= overflow
            } else {
                sourceHeight = max(64, sourceHeight - (overflow - max(0, resultHeight - 68)))
                resultHeight = 68
            }
        }

        let height = min(maximumHeight, fixedHeight + sourceHeight + resultHeight)
        return TranslationWindowLayout(
            contentSize: CGSize(width: width, height: height),
            sourceHeight: sourceHeight,
            resultHeight: resultHeight
        )
    }

    @MainActor
    private static func measuredHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height)
    }
}

@MainActor
final class TranslationWindowLayoutModel: ObservableObject {
    @Published var value: TranslationWindowLayout

    init(value: TranslationWindowLayout) {
        self.value = value
    }
}

@MainActor
final class TranslationEditorWindowController: NSObject, NSWindowDelegate, ScreenshotTranslationPresenting {
    private static let widthDefaultsKey = "quickTools.translationWindowWidth"

    private let window: NSPanel
    private let store: TranslationEditorStore
    private let layoutModel: TranslationWindowLayoutModel
    private let onClose: () -> Void
    private let targetScreen: NSScreen?
    private var cancellables = Set<AnyCancellable>()
    private var didClose = false
    private var isApplyingContentSize = false
    private var pendingResizeRequest: (
        source: String,
        translation: String,
        state: TranslationEditorStore.State
    )?

    init(
        snapshot: TranslationTargetSnapshot,
        nonChineseTarget: QuickToolLanguage,
        chineseTarget: QuickToolLanguage,
        engine: TranslationEngine,
        onlineConfiguration: AITranslationConfiguration?,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let availableFrame = targetScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let savedWidth = Self.savedWidth(in: availableFrame)
        let formattedInitialSource = TranslationTextFormatter.addingSemanticLineBreaks(snapshot.originalText)
        let initialLayout = TranslationWindowLayout.calculate(
            source: formattedInitialSource,
            translation: "",
            availableFrame: availableFrame,
            preferredWidth: savedWidth
        )
        layoutModel = TranslationWindowLayoutModel(value: initialLayout)
        window = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialLayout.contentSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        var closeAfterReplacement: (() -> Void)?
        store = TranslationEditorStore(
            snapshot: snapshot,
            nonChineseTarget: nonChineseTarget,
            chineseTarget: chineseTarget,
            engine: engine,
            onlineConfiguration: onlineConfiguration,
            onReplaced: { closeAfterReplacement?() }
        )
        super.init()
        closeAfterReplacement = { [weak self] in self?.window.close() }
        window.title = "元圭与 VCC 翻译小屋"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.minSize = NSSize(width: 400, height: 280)
        window.maxSize = NSSize(width: availableFrame.width - 16, height: availableFrame.height - 16)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: TranslationEditorView(
            store: store,
            layout: layoutModel,
            close: { [weak window] in window?.close() }
        ))
        centerWindow(in: availableFrame)
        Publishers.CombineLatest3(store.$editableSourceText, store.$translatedText, store.$state)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] source, translation, state in
                self?.resizeForContent(source: source, translation: translation, state: state)
            }
            .store(in: &cancellables)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateSourceText(_ text: String) {
        store.updateEditableSourceText(text)
    }

    func setMessage(_ message: String?) {
        store.message = message
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        store.clearSensitiveState()
        onClose()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !isApplyingContentSize else { return }
        let width = window.contentLayoutRect.width
        UserDefaults.standard.set(Double(width), forKey: Self.widthDefaultsKey)
        let request = pendingResizeRequest ?? (
            source: store.editableSourceText,
            translation: store.translatedText,
            state: store.state
        )
        pendingResizeRequest = nil
        resizeForContent(source: request.source, translation: request.translation, state: request.state)
    }

    private func resizeForContent(
        source: String,
        translation: String,
        state: TranslationEditorStore.State
    ) {
        guard !window.inLiveResize else {
            pendingResizeRequest = (source, translation, state)
            return
        }
        let availableFrame = window.screen?.visibleFrame ?? targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let resultForMeasurement: String
        if case let .failed(message) = state, translation.isEmpty {
            resultForMeasurement = message
        } else {
            resultForMeasurement = translation
        }
        let layout = TranslationWindowLayout.calculate(
            source: source,
            translation: resultForMeasurement,
            availableFrame: availableFrame,
            preferredWidth: window.contentLayoutRect.width
        )
        guard layout != layoutModel.value else { return }

        let oldFrame = window.frame
        let top = oldFrame.maxY
        let centerX = oldFrame.midX
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: layout.contentSize)
        ).size
        var frame = CGRect(
            x: centerX - targetFrameSize.width / 2,
            y: top - targetFrameSize.height,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        frame.origin.x = min(max(frame.origin.x, availableFrame.minX + 8), availableFrame.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.origin.y, availableFrame.minY + 8), availableFrame.maxY - frame.height - 8)

        isApplyingContentSize = true
        layoutModel.value = layout
        window.setFrame(frame, display: true)
        isApplyingContentSize = false
    }

    private static func savedWidth(in availableFrame: CGRect) -> CGFloat {
        let maximum = max(400, availableFrame.width - 32)
        let stored = CGFloat(UserDefaults.standard.double(forKey: widthDefaultsKey))
        guard stored.isFinite, stored >= 400 else { return min(440, maximum) }
        return min(stored, maximum)
    }

    private func centerWindow(in visibleFrame: CGRect) {
        var frame = window.frame
        frame.origin = CGPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrame(frame, display: false)
    }
}
