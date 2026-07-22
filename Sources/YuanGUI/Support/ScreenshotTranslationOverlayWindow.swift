import AppKit
import SwiftUI
import Translation

struct ScreenshotTranslationBlock: Equatable, Identifiable, Sendable {
    let id: Int
    let normalizedRect: CGRect
    let text: String
    let backgroundColor: OCRBackgroundColor
}

struct ScreenshotTranslationDisplayBlock: Equatable, Identifiable, Sendable {
    let id: Int
    let frame: CGRect
    let text: String
    let fontSize: CGFloat
    let backgroundColor: OCRBackgroundColor
}

@MainActor
final class ScreenshotTranslationOverlayModel: ObservableObject {
    let image: CGImage
    @Published var regions: [OCRTextRegion] = []
    @Published var comparisonEnabled = false

    init(image: CGImage) {
        self.image = image
    }
}

@MainActor
final class ScreenshotTranslationOverlayWindowController: NSObject, NSWindowDelegate, ScreenshotTranslationPresenting {
    private let window: ScreenshotTranslationOverlayPanel
    private let toolbarWindow: ScreenshotTranslationOverlayPanel
    private let store: TranslationEditorStore
    private let model: ScreenshotTranslationOverlayModel
    private let onClose: () -> Void
    private var comparisonWindow: ScreenshotTranslationOverlayPanel?
    private var standardFrame: CGRect
    private var escapeMonitor: Any?
    private var toolbarDragStart: (mouse: CGPoint, window: CGRect, comparison: CGRect?)?
    private var didClose = false

    init(
        selection: ScreenshotSelection,
        image: CGImage,
        snapshot: TranslationTargetSnapshot,
        nonChineseTarget: QuickToolLanguage,
        chineseTarget: QuickToolLanguage,
        engine: TranslationEngine,
        onlineConfiguration: AITranslationConfiguration?,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        standardFrame = Self.overlayFrame(for: selection)
        model = ScreenshotTranslationOverlayModel(image: image)
        window = ScreenshotTranslationOverlayPanel(
            contentRect: standardFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarWindow = ScreenshotTranslationOverlayPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 160, height: 40)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        store = TranslationEditorStore(
            snapshot: snapshot,
            nonChineseTarget: nonChineseTarget,
            chineseTarget: chineseTarget,
            engine: engine,
            onlineConfiguration: onlineConfiguration,
            onReplaced: {}
        )
        super.init()
        configure(panel: window, title: "截图翻译图文覆盖层", shadow: true)
        configure(panel: toolbarWindow, title: "截图翻译工具栏", shadow: true)
        toolbarWindow.level = .popUpMenu
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.onEscape = { [weak self] in self?.close() }
        toolbarWindow.onEscape = { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: ScreenshotTranslationOverlayView(model: model, store: store))
        toolbarWindow.contentView = NSHostingView(rootView: ScreenshotTranslationToolbarView(
            model: model,
            store: store,
            dragToPointer: { [weak self] ended in self?.dragToolbarToPointer(ended: ended) },
            toggleComparison: { [weak self] in self?.toggleComparison() },
            close: { [weak self] in self?.close() }
        ))
        positionToolbar()
    }

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    func show() {
        window.orderFrontRegardless()
        toolbarWindow.orderFrontRegardless()
        window.makeKey()
        installEscapeMonitor()
    }

    func close() {
        window.close()
    }

    func updateSourceText(_ text: String) {
        store.updateEditableSourceText(text)
    }

    func updateRecognition(_ recognition: OCRRecognition) {
        model.regions = recognition.regions
        store.updateEditableSourceText(recognition.text)
    }

    func setMessage(_ message: String?) {
        store.message = message
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        comparisonWindow?.orderOut(nil)
        comparisonWindow = nil
        toolbarWindow.orderOut(nil)
        model.regions = []
        store.clearSensitiveState()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        if comparisonWindow == nil { standardFrame = window.frame }
        positionToolbar()
    }

    nonisolated static func overlayFrame(for selection: ScreenshotSelection) -> CGRect {
        selection.globalRect
    }

    nonisolated static var panelCollectionBehavior: NSWindow.CollectionBehavior {
        [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    nonisolated static func toolbarFrame(
        for contentFrame: CGRect,
        toolbarSize: CGSize,
        visibleFrame: CGRect,
        spacing: CGFloat = 6
    ) -> CGRect {
        let x = min(max(contentFrame.maxX - toolbarSize.width, visibleFrame.minX), visibleFrame.maxX - toolbarSize.width)
        let y: CGFloat
        if contentFrame.maxY + spacing + toolbarSize.height <= visibleFrame.maxY {
            y = contentFrame.maxY + spacing
        } else {
            y = max(visibleFrame.minY, contentFrame.minY - spacing - toolbarSize.height)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }

    nonisolated static func comparisonFrames(
        for contentFrame: CGRect,
        visibleFrame: CGRect,
        spacing: CGFloat = 12
    ) -> (original: CGRect, translated: CGRect) {
        if contentFrame.width * 2 + spacing <= visibleFrame.width {
            let pairWidth = contentFrame.width * 2 + spacing
            let x = min(max(contentFrame.midX - pairWidth / 2, visibleFrame.minX), visibleFrame.maxX - pairWidth)
            let y = min(max(contentFrame.minY, visibleFrame.minY), visibleFrame.maxY - contentFrame.height)
            return (
                CGRect(x: x, y: y, width: contentFrame.width, height: contentFrame.height),
                CGRect(x: x + contentFrame.width + spacing, y: y, width: contentFrame.width, height: contentFrame.height)
            )
        }
        if contentFrame.height * 2 + spacing <= visibleFrame.height {
            let pairHeight = contentFrame.height * 2 + spacing
            let y = min(max(contentFrame.midY - pairHeight / 2, visibleFrame.minY), visibleFrame.maxY - pairHeight)
            let x = min(max(contentFrame.minX, visibleFrame.minX), visibleFrame.maxX - contentFrame.width)
            return (
                CGRect(x: x, y: y + contentFrame.height + spacing, width: contentFrame.width, height: contentFrame.height),
                CGRect(x: x, y: y, width: contentFrame.width, height: contentFrame.height)
            )
        }
        let horizontalScale = min(
            (visibleFrame.width - spacing) / max(1, contentFrame.width * 2),
            visibleFrame.height / max(1, contentFrame.height)
        )
        let verticalScale = min(
            visibleFrame.width / max(1, contentFrame.width),
            (visibleFrame.height - spacing) / max(1, contentFrame.height * 2)
        )
        if horizontalScale >= verticalScale {
            let scale = min(1, horizontalScale)
            let size = CGSize(width: contentFrame.width * scale, height: contentFrame.height * scale)
            let pairWidth = size.width * 2 + spacing
            let x = visibleFrame.midX - pairWidth / 2
            let y = visibleFrame.midY - size.height / 2
            return (
                CGRect(origin: CGPoint(x: x, y: y), size: size),
                CGRect(origin: CGPoint(x: x + size.width + spacing, y: y), size: size)
            )
        }
        let scale = min(1, verticalScale)
        let size = CGSize(width: contentFrame.width * scale, height: contentFrame.height * scale)
        let pairHeight = size.height * 2 + spacing
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.midY - pairHeight / 2
        return (
            CGRect(origin: CGPoint(x: x, y: y + size.height + spacing), size: size),
            CGRect(origin: CGPoint(x: x, y: y), size: size)
        )
    }

    nonisolated static func translationBlocks(
        regions: [OCRTextRegion],
        translatedText: String
    ) -> [ScreenshotTranslationBlock] {
        guard !regions.isEmpty else { return [] }
        let lines = translatedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let assignedLines = lines.count == regions.count
            ? lines
            : distributedTranslation(translatedText, matching: regions)
        return translationBlocks(regions: regions, translatedLines: assignedLines)
    }

    nonisolated static func translationBlocks(
        regions: [OCRTextRegion],
        translatedLines: [String]
    ) -> [ScreenshotTranslationBlock] {
        zip(regions, translatedLines).enumerated().compactMap { index, pair in
            let translation = pair.1.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else { return nil }
            let region = pair.0
            let expansion = max(1, CGFloat(translation.count) / CGFloat(max(1, region.text.count)))
            let rightBoundary = availableRightBoundary(for: index, in: regions)
            let width = min(
                max(region.normalizedRect.width, rightBoundary - region.normalizedRect.minX),
                region.normalizedRect.width * expansion
            )
            return ScreenshotTranslationBlock(
                id: index,
                normalizedRect: CGRect(
                    x: region.normalizedRect.minX,
                    y: region.normalizedRect.minY,
                    width: width,
                    height: region.normalizedRect.height
                ),
                text: translation,
                backgroundColor: region.backgroundColor
            )
        }
    }

    @MainActor
    static func displayBlocks(
        from blocks: [ScreenshotTranslationBlock],
        in size: CGSize
    ) -> [ScreenshotTranslationDisplayBlock] {
        guard size.width > 0, size.height > 0 else { return [] }
        let bounds = CGRect(origin: .zero, size: size)
        let anchors = blocks.map { block in
            clampedDisplayRect(for: block.normalizedRect, in: size, bounds: bounds)
        }
        return blocks.enumerated().map { index, block in
            let frame = readableFrame(for: index, anchors: anchors, bounds: bounds)
            return ScreenshotTranslationDisplayBlock(
                id: block.id,
                frame: frame,
                text: block.text,
                fontSize: fittingFontSize(for: block.text, in: frame.size),
                backgroundColor: block.backgroundColor
            )
        }
    }

    @MainActor
    private static func fittingFontSize(for text: String, in size: CGSize) -> CGFloat {
        let maximum = max(6, min(40, (size.height - 2) * 0.9))
        let availableWidth = max(1, size.width - 6)
        let availableHeight = max(1, size.height - 2)
        func fits(_ fontSize: CGFloat) -> Bool {
            let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
            let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            let measuredHeight = ceil(font.ascender - font.descender + font.leading)
            return measuredWidth <= availableWidth && measuredHeight <= availableHeight
        }
        if fits(maximum) { return maximum }
        var lower: CGFloat = 5
        var upper = maximum
        for _ in 0..<12 {
            let candidate = (lower + upper) / 2
            if fits(candidate) { lower = candidate } else { upper = candidate }
        }
        return max(5, floor(lower * 10) / 10)
    }

    nonisolated private static func clampedDisplayRect(
        for normalizedRect: CGRect,
        in size: CGSize,
        bounds: CGRect
    ) -> CGRect {
        let anchor = ScreenshotTranslationOverlayView.displayRect(for: normalizedRect, in: size)
            .intersection(bounds)
        return CGRect(
            x: max(0, anchor.minX),
            y: max(0, anchor.minY),
            width: min(max(1, anchor.width), max(1, size.width - anchor.minX)),
            height: min(max(1, anchor.height), max(1, size.height - anchor.minY))
        )
    }

    nonisolated private static func readableFrame(
        for index: Int,
        anchors: [CGRect],
        bounds: CGRect
    ) -> CGRect {
        let anchor = anchors[index]
        let verticallyRelevant = anchors.enumerated().compactMap { candidateIndex, candidate -> (Int, CGRect)? in
            guard candidateIndex != index else { return nil }
            let horizontalOverlap = max(0, min(anchor.maxX, candidate.maxX) - max(anchor.minX, candidate.minX))
            guard horizontalOverlap >= min(anchor.width, candidate.width) * 0.2 else { return nil }
            return (candidateIndex, candidate)
        }
        let above = verticallyRelevant
            .filter { candidateIndex, candidate in
                candidate.midY < anchor.midY
                    || (abs(candidate.midY - anchor.midY) < 0.5 && candidateIndex < index)
            }
            .max { $0.1.midY < $1.1.midY }
        let below = verticallyRelevant
            .filter { candidateIndex, candidate in
                candidate.midY > anchor.midY
                    || (abs(candidate.midY - anchor.midY) < 0.5 && candidateIndex > index)
            }
            .min { $0.1.midY < $1.1.midY }
        let separation: CGFloat = 1
        let topLimit = above.map { ($0.1.midY + anchor.midY) / 2 + separation / 2 } ?? bounds.minY
        let bottomLimit = below.map { (anchor.midY + $0.1.midY) / 2 - separation / 2 } ?? bounds.maxY
        let slotTop = min(max(topLimit, bounds.minY), anchor.midY)
        let slotBottom = max(min(bottomLimit, bounds.maxY), anchor.midY)
        let slotHeight = max(1, slotBottom - slotTop)
        let preferredExpansion = min(6, max(1, anchor.height * 0.22))
        let height = min(slotHeight, anchor.height + preferredExpansion * 2)
        let centeredTop = anchor.midY - height / 2
        let top = min(max(centeredTop, slotTop), slotBottom - height)
        return CGRect(
            x: anchor.minX,
            y: top,
            width: anchor.width,
            height: height
        )
    }

    nonisolated private static func availableRightBoundary(
        for index: Int,
        in regions: [OCRTextRegion]
    ) -> CGFloat {
        let region = regions[index].normalizedRect
        let neighborX = regions.enumerated().compactMap { candidateIndex, candidate -> CGFloat? in
            guard candidateIndex != index else { return nil }
            let rect = candidate.normalizedRect
            guard rect.minX > region.minX else { return nil }
            let verticalOverlap = max(0, min(region.maxY, rect.maxY) - max(region.minY, rect.minY))
            guard verticalOverlap >= min(region.height, rect.height) * 0.4 else { return nil }
            return rect.minX
        }.min()
        return max(region.maxX, (neighborX.map { $0 - 0.008 }) ?? 1)
    }

    nonisolated private static func distributedTranslation(
        _ text: String,
        matching regions: [OCRTextRegion]
    ) -> [String] {
        guard !regions.isEmpty else { return [] }
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !characters.isEmpty else { return Array(repeating: "", count: regions.count) }
        guard characters.count >= regions.count else {
            return [String(characters)] + Array(repeating: "", count: regions.count - 1)
        }
        let totalWeight = max(1, regions.reduce(0) { $0 + max(1, $1.text.count) })
        var consumedWeight = 0
        var start = 0
        return regions.enumerated().map { index, region in
            guard start < characters.count else { return "" }
            if index == regions.count - 1 {
                return String(characters[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            consumedWeight += max(1, region.text.count)
            let desired = max(start + 1, Int((Double(consumedWeight) / Double(totalWeight) * Double(characters.count)).rounded()))
            let upperBound = min(characters.count, max(start + 1, characters.count - (regions.count - index - 1)))
            var end = min(desired, upperBound)
            for offset in 0...12 {
                let candidates = [end - offset, end + offset]
                if let boundary = candidates.first(where: { candidate in
                    candidate > start && candidate < upperBound
                        && (characters[candidate - 1].isWhitespace || characters[candidate].isWhitespace)
                }) {
                    end = boundary
                    break
                }
            }
            let result = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            start = end
            return result
        }
    }

    private func configure(panel: ScreenshotTranslationOverlayPanel, title: String, shadow: Bool) {
        panel.title = title
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = shadow
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = Self.panelCollectionBehavior
    }

    private func positionToolbar() {
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame.insetBy(dx: -200, dy: -200)
        toolbarWindow.setFrame(Self.toolbarFrame(
            for: window.frame,
            toolbarSize: toolbarWindow.frame.size,
            visibleFrame: visibleFrame
        ), display: true)
    }

    private func dragToolbarToPointer(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if toolbarDragStart == nil {
            toolbarDragStart = (mouse, window.frame, comparisonWindow?.frame)
        }
        guard let start = toolbarDragStart else { return }
        let offset = CGSize(width: mouse.x - start.mouse.x, height: mouse.y - start.mouse.y)
        window.setFrameOrigin(CGPoint(
            x: start.window.minX + offset.width,
            y: start.window.minY + offset.height
        ))
        if let comparisonWindow, let comparisonFrame = start.comparison {
            comparisonWindow.setFrameOrigin(CGPoint(
                x: comparisonFrame.minX + offset.width,
                y: comparisonFrame.minY + offset.height
            ))
        }
        if ended { toolbarDragStart = nil }
    }

    private func toggleComparison() {
        if let comparisonWindow {
            comparisonWindow.orderOut(nil)
            self.comparisonWindow = nil
            model.comparisonEnabled = false
            window.setFrame(standardFrame, display: true)
            positionToolbar()
            window.makeKey()
            return
        }
        standardFrame = window.frame
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let frames = Self.comparisonFrames(for: window.frame, visibleFrame: visibleFrame)
        let original = ScreenshotTranslationOverlayPanel(
            contentRect: frames.original,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel: original, title: "截图翻译原文对照", shadow: true)
        original.onEscape = { [weak self] in self?.close() }
        original.contentView = NSHostingView(rootView: ScreenshotOriginalImageView(image: model.image))
        comparisonWindow = original
        model.comparisonEnabled = true
        window.setFrame(frames.translated, display: true)
        original.orderFrontRegardless()
        window.orderFrontRegardless()
        toolbarWindow.orderFrontRegardless()
        positionToolbar()
        window.makeKey()
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window.isVisible == true else { return event }
            self?.close()
            return nil
        }
    }
}

private final class ScreenshotTranslationOverlayPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct ScreenshotOriginalImageView: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipped()
    }
}

private struct ScreenshotTranslationOverlayView: View {
    @ObservedObject var model: ScreenshotTranslationOverlayModel
    @ObservedObject var store: TranslationEditorStore
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(decorative: model.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .allowsHitTesting(false)
                translationLayer(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: translationRequestID) {
            guard !store.editableSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await requestTranslation()
        }
        .translationTask(configuration) { session in
            await store.performLineTranslations(using: session, sourceLines: model.regions.map(\.text))
        }
    }

    @ViewBuilder
    private func translationLayer(size: CGSize) -> some View {
        if store.editableSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusPill(store.message ?? "正在识别截图文字…", showsProgress: store.message?.hasPrefix("正在") == true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.state == .translating {
            statusPill("正在翻译…", showsProgress: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case let .failed(message) = store.state {
            VStack(spacing: 7) {
                Text(message).font(.caption).multilineTextAlignment(.center)
                Button("重试") { Task { await requestTranslation() } }.controlSize(.small)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let sourceBlocks = ScreenshotTranslationOverlayWindowController.translationBlocks(
                regions: model.regions,
                translatedLines: store.translatedLines
            )
            let blocks = ScreenshotTranslationOverlayWindowController.displayBlocks(from: sourceBlocks, in: size)
            ZStack(alignment: .topLeading) {
                ForEach(blocks) { block in translatedBlock(block) }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    private func translatedBlock(_ block: ScreenshotTranslationDisplayBlock) -> some View {
        Text(block.text)
            .font(.system(size: block.fontSize, weight: .regular))
            .foregroundStyle(block.backgroundColor.isDark ? Color.white : Color.black)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 2)
            .frame(width: max(block.frame.width, 1), height: max(block.frame.height, 1), alignment: .leading)
            .background(Color(
                red: block.backgroundColor.red,
                green: block.backgroundColor.green,
                blue: block.backgroundColor.blue
            ))
            .position(x: block.frame.midX, y: block.frame.midY)
            .clipped()
    }

    private func statusPill(_ text: String, showsProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView().controlSize(.small) }
            Text(text).font(.caption).lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 9))
    }

    private func requestTranslation() async {
        let sourceLines = model.regions.map(\.text)
        if store.usesShortcutTranslation {
            configuration = nil
            await store.performShortcutLineTranslations(sourceLines: sourceLines)
        } else if store.usesOnlineTranslation {
            configuration = nil
            await store.performOnlineLineTranslations(sourceLines: sourceLines)
        } else {
            var newConfiguration = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: store.targetLanguage.rawValue)
            )
            newConfiguration.invalidate()
            configuration = newConfiguration
        }
    }

    private var translationRequestID: String {
        store.targetLanguage.rawValue + "\u{0}" + store.editableSourceText
    }

    nonisolated static func displayRect(for normalizedRect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.minX * size.width,
            y: (1 - normalizedRect.maxY) * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height
        )
    }
}

private struct ScreenshotTranslationToolbarView: View {
    @ObservedObject var model: ScreenshotTranslationOverlayModel
    @ObservedObject var store: TranslationEditorStore
    let dragToPointer: (Bool) -> Void
    let toggleComparison: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .help("拖动截图翻译窗口")
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { _ in dragToPointer(false) }
                    .onEnded { _ in dragToPointer(true) })
            Button {
                store.copyTranslation()
            } label: {
                Image(systemName: store.message == "已复制译文" ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .disabled(store.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("复制译文")
            Button(action: toggleComparison) {
                Image(systemName: model.comparisonEnabled ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }
            .buttonStyle(.plain)
            .help(model.comparisonEnabled ? "关闭中英对照" : "同时显示原文与译文")
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("关闭截图翻译（Esc）")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(width: 160, height: 40)
        .background(.ultraThickMaterial, in: Capsule())
    }
}
