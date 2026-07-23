import AppKit
import SwiftUI
import Translation

struct ScreenshotTranslationBlock: Equatable, Identifiable, Sendable {
    let id: Int
    let normalizedRect: CGRect
    let text: String
    let backgroundColor: OCRBackgroundColor
    let sourceFontScale: CGFloat
    let role: OCRTextRole

    init(
        id: Int,
        normalizedRect: CGRect,
        text: String,
        backgroundColor: OCRBackgroundColor,
        sourceFontScale: CGFloat? = nil,
        role: OCRTextRole = .body
    ) {
        self.id = id
        self.normalizedRect = normalizedRect
        self.text = text
        self.backgroundColor = backgroundColor
        self.sourceFontScale = sourceFontScale ?? normalizedRect.height
        self.role = role
    }
}

struct ScreenshotTranslationDisplayBlock: Equatable, Identifiable, Sendable {
    let id: Int
    let frame: CGRect
    /// The original OCR area that must be painted over even when the translated
    /// text is moved vertically or uses a different width.
    let coverageFrame: CGRect
    let text: String
    let fontSize: CGFloat
    let backgroundColor: OCRBackgroundColor
    let lineSpacing: CGFloat
    let usesOverflowCard: Bool

    init(
        id: Int,
        frame: CGRect,
        coverageFrame: CGRect,
        text: String,
        fontSize: CGFloat,
        backgroundColor: OCRBackgroundColor,
        lineSpacing: CGFloat = 1,
        usesOverflowCard: Bool = false
    ) {
        self.id = id
        self.frame = frame
        self.coverageFrame = coverageFrame
        self.text = text
        self.fontSize = fontSize
        self.backgroundColor = backgroundColor
        self.lineSpacing = lineSpacing
        self.usesOverflowCard = usesOverflowCard
    }
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
    private var magnifyMonitor: Any?
    private var overlayDragStart: (mouse: CGPoint, window: CGRect)?
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
            styleMask: Self.overlayStyleMask,
            backing: .buffered,
            defer: false
        )
        toolbarWindow = ScreenshotTranslationOverlayPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 224, height: 40)),
            styleMask: Self.auxiliaryOverlayStyleMask,
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
        // SwiftUI owns direct image dragging. Enabling AppKit background dragging here
        // would move the same panel twice for one mouse gesture and causes edge jitter.
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.onEscape = { [weak self] in self?.close() }
        toolbarWindow.onEscape = { [weak self] in self?.close() }
        window.contentView = ScreenshotTranslationFirstMouseHostingView(rootView: ScreenshotTranslationOverlayView(
            model: model,
            store: store,
            dragToPointer: { [weak self] ended in self?.dragOverlayToPointer(ended: ended) }
        ))
        toolbarWindow.contentView = ScreenshotTranslationFirstMouseHostingView(rootView: ScreenshotTranslationToolbarView(
            model: model,
            store: store,
            dragToPointer: { [weak self] ended in self?.dragOverlayToPointer(ended: ended) },
            zoomOut: { [weak self] in self?.scaleOverlay(by: 0.82) },
            zoomIn: { [weak self] in self?.scaleOverlay(by: 1.22) },
            toggleComparison: { [weak self] in self?.toggleComparison() },
            close: { [weak self] in self?.close() }
        ))
        positionToolbar()
        window.addChildWindow(toolbarWindow, ordered: .above)
    }

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
    }

    func show() {
        TranslationPerformance.measureSync(.presentation) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            toolbarWindow.orderFrontRegardless()
        }
        installInputMonitors()
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
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
        magnifyMonitor = nil
        comparisonWindow?.orderOut(nil)
        if let comparisonWindow { window.removeChildWindow(comparisonWindow) }
        comparisonWindow = nil
        window.removeChildWindow(toolbarWindow)
        toolbarWindow.orderOut(nil)
        model.regions = []
        store.clearSensitiveState()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        if comparisonWindow == nil { standardFrame = window.frame }
    }

    nonisolated static func overlayFrame(for selection: ScreenshotSelection) -> CGRect {
        selection.globalRect
    }

    nonisolated static var panelCollectionBehavior: NSWindow.CollectionBehavior {
        [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    nonisolated static var overlayStyleMask: NSWindow.StyleMask {
        [.borderless, .resizable]
    }

    nonisolated static var auxiliaryOverlayStyleMask: NSWindow.StyleMask {
        [.borderless]
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
        } else if contentFrame.minY - spacing - toolbarSize.height >= visibleFrame.minY {
            y = contentFrame.minY - spacing - toolbarSize.height
        } else if visibleFrame.maxY - contentFrame.maxY >= contentFrame.minY - visibleFrame.minY {
            // Neither side currently fits. Keep the toolbar outside the image and let
            // the group constraint move both windows together after dragging ends.
            y = contentFrame.maxY + spacing
        } else {
            y = contentFrame.minY - spacing - toolbarSize.height
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }

    nonisolated static func scaledFrame(
        for frame: CGRect,
        by factor: CGFloat,
        visibleFrame: CGRect,
        focalPoint: CGPoint? = nil,
        minimumWidth: CGFloat = 240
    ) -> CGRect {
        guard frame.width > 0, frame.height > 0, factor > 0 else { return frame }
        let aspectRatio = frame.width / frame.height
        var width = max(minimumWidth, frame.width * factor)
        var height = width / aspectRatio
        let maximumSize = CGSize(width: visibleFrame.width * 0.96, height: visibleFrame.height * 0.92)
        if width > maximumSize.width || height > maximumSize.height {
            let scale = min(maximumSize.width / width, maximumSize.height / height)
            width *= scale
            height *= scale
        }
        let focal = focalPoint ?? CGPoint(x: frame.midX, y: frame.midY)
        let normalizedFocalX = min(1, max(0, (focal.x - frame.minX) / frame.width))
        let normalizedFocalY = min(1, max(0, (focal.y - frame.minY) / frame.height))
        let proposed = CGRect(
            x: focal.x - width * normalizedFocalX,
            y: focal.y - height * normalizedFocalY,
            width: width,
            height: height
        )
        return CGRect(
            x: min(max(proposed.minX, visibleFrame.minX), visibleFrame.maxX - proposed.width),
            y: min(max(proposed.minY, visibleFrame.minY), visibleFrame.maxY - proposed.height),
            width: proposed.width,
            height: proposed.height
        )
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
        let groups = translatableSentenceGroups(regions: regions)
        guard !groups.isEmpty else { return [] }
        let lines = translatedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let assignedLines = lines.count == groups.count
            ? lines
            : distributedTranslation(
                translatedText,
                matching: groups.map(paragraphProxyRegion)
            )
        return translationBlocks(regions: regions, translatedLines: assignedLines)
    }

    nonisolated static func translationBlocks(
        regions: [OCRTextRegion],
        translatedLines: [String]
    ) -> [ScreenshotTranslationBlock] {
        let groups = translatableSentenceGroups(regions: regions)
        if translatedLines.count == groups.count {
            return makeParagraphTranslationBlocks(groups: groups, translatedParagraphs: translatedLines)
        }
        let joined = translatedLines.joined(separator: "\n")
        return makeParagraphTranslationBlocks(
            groups: groups,
            translatedParagraphs: distributedTranslation(joined, matching: groups.map(paragraphProxyRegion))
        )
    }

    nonisolated static func translatableVisualLines(regions: [OCRTextRegion]) -> [String] {
        translatableRegions(regions: regions).map(\.text)
    }

    nonisolated static func translatableParagraphs(regions: [OCRTextRegion]) -> [String] {
        translatableSentenceGroups(regions: regions).map(paragraphSourceText)
    }

    nonisolated static func translatableSentences(regions: [OCRTextRegion]) -> [String] {
        translatableSentenceGroups(regions: regions).map(paragraphSourceText)
    }

    nonisolated private static func translatableRegions(regions: [OCRTextRegion]) -> [OCRTextRegion] {
        regions.filter { !$0.isProtectedText }.sorted { lhs, rhs in
            if lhs.readingOrder != rhs.readingOrder { return lhs.readingOrder < rhs.readingOrder }
            if abs(lhs.normalizedRect.midY - rhs.normalizedRect.midY) > 0.001 {
                return lhs.normalizedRect.midY > rhs.normalizedRect.midY
            }
            return lhs.normalizedRect.minX < rhs.normalizedRect.minX
        }
    }

    /// Builds stable translation units from visual OCR lines. Wrapped lines belonging to one
    /// sentence are merged, while controls, metadata and completed sentences remain independent.
    /// This gives every translation engine one semantic unit and one unambiguous screen anchor.
    nonisolated private static func translatableSentenceGroups(regions: [OCRTextRegion]) -> [[OCRTextRegion]] {
        let ordered = translatableRegions(regions: regions)
        var groups: [[OCRTextRegion]] = []
        for region in ordered {
            guard var current = groups.popLast() else {
                groups.append([region])
                continue
            }
            if shouldJoinSentenceLine(previous: current.last!, current: region) {
                current.append(region)
                groups.append(current)
            } else {
                groups.append(current)
                groups.append([region])
            }
        }
        return groups
    }

    nonisolated private static func shouldJoinSentenceLine(
        previous: OCRTextRegion,
        current: OCRTextRegion
    ) -> Bool {
        guard previous.paragraphIndex == current.paragraphIndex,
              previous.columnIndex == current.columnIndex,
              previous.role == .body,
              current.role == .body else { return false }
        let previousText = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousText.isEmpty, !currentText.isEmpty,
              !endsSemanticSentence(previousText),
              !looksLikeCompactMetadata(currentText) else { return false }
        let previousRect = previous.normalizedRect
        let currentRect = current.normalizedRect
        let verticalGap = max(0, previousRect.minY - currentRect.maxY)
        let lineHeight = max(previousRect.height, currentRect.height)
        let aligned = abs(previousRect.minX - currentRect.minX) <= max(0.035, lineHeight * 1.2)
        let fontRatio = max(previous.estimatedFontScale, current.estimatedFontScale)
            / max(0.0001, min(previous.estimatedFontScale, current.estimatedFontScale))
        return currentRect.midY < previousRect.midY
            && verticalGap <= lineHeight * 1.35
            && aligned
            && fontRatio <= 1.4
    }

    nonisolated private static func endsSemanticSentence(_ text: String) -> Bool {
        text.range(of: #"[.!?。！？；;：:]\s*[\"'”’）)]*$"#, options: .regularExpression) != nil
    }

    nonisolated private static func looksLikeCompactMetadata(_ text: String) -> Bool {
        if text.count > 30 { return false }
        return text.range(
            of: #"^(?:[•●★☆]\s*)?(?:[\p{L}\p{N}+#._-]+(?:\s*[/|·]\s*[\p{L}\p{N}+#._-]+)?)(?:\s+[★☆]?\s*\d+(?:\.\d+)?[kKmM千]?)?$"#,
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func paragraphSourceText(_ group: [OCRTextRegion]) -> String {
        group.enumerated().reduce(into: "") { result, item in
            let (index, region) = item
            guard index > 0 else {
                result = region.text
                return
            }
            let previous = group[index - 1]
            let keepsVisualBreak = region.role == .listItem
                || previous.role == .listItem
                || region.text.trimmingCharacters(in: .whitespaces).hasPrefix("•")
            result += keepsVisualBreak ? "\n" : " "
            result += region.text
        }
    }

    nonisolated private static func paragraphProxyRegion(_ group: [OCRTextRegion]) -> OCRTextRegion {
        let rect = group.dropFirst().reduce(group.first?.normalizedRect ?? .zero) {
            $0.union($1.normalizedRect)
        }
        return OCRTextRegion(
            text: paragraphSourceText(group),
            normalizedRect: rect,
            backgroundColor: group.first?.backgroundColor ?? .white,
            estimatedFontScale: group.map(\.estimatedFontScale).sorted()[group.count / 2],
            role: group.first?.role ?? .body
        )
    }

    nonisolated private static func makeParagraphTranslationBlocks(
        groups: [[OCRTextRegion]],
        translatedParagraphs: [String]
    ) -> [ScreenshotTranslationBlock] {
        let proxies = groups.map(paragraphProxyRegion)
        return zip(proxies, translatedParagraphs).enumerated().compactMap { index, pair in
            let source = pair.0
            let translation = TranslationTextFormatter.addingSemanticLineBreaks(pair.1)
            guard !translation.isEmpty else { return nil }
            return ScreenshotTranslationBlock(
                id: index,
                normalizedRect: source.normalizedRect,
                text: translation,
                backgroundColor: source.backgroundColor,
                sourceFontScale: source.estimatedFontScale,
                role: source.role
            )
        }
    }

    static func displayBlocks(
        from blocks: [ScreenshotTranslationBlock],
        in size: CGSize
    ) -> [ScreenshotTranslationDisplayBlock] {
        displayLayout(from: blocks, in: size).blocks
    }

    static func displayLayout(
        from blocks: [ScreenshotTranslationBlock],
        in size: CGSize
    ) -> ScreenshotTranslationLayout {
        TranslationPerformance.measureSync(.layout) {
            ScreenshotTranslationLayoutEngine.layout(blocks: blocks, in: size)
        }
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
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
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

    private func scaleOverlay(by factor: CGFloat, around focalPoint: CGPoint? = nil) {
        guard factor > 0 else { return }
        let focal = focalPoint ?? CGPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(focal) })
            ?? window.screen
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let resizedFrame = Self.scaledFrame(
            for: window.frame,
            by: factor,
            visibleFrame: visibleFrame,
            focalPoint: focal
        )

        if let comparisonWindow {
            let frames = Self.comparisonFrames(
                for: resizedFrame,
                visibleFrame: visibleFrame
            )
            comparisonWindow.setFrame(frames.original, display: true)
            window.setFrame(frames.translated, display: true)
        } else {
            window.setFrame(resizedFrame, display: true)
            standardFrame = resizedFrame
        }
        positionToolbar()
    }

    private func dragOverlayToPointer(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if overlayDragStart == nil {
            overlayDragStart = (mouse, window.frame)
        }
        guard let start = overlayDragStart else { return }
        let offset = CGSize(width: mouse.x - start.mouse.x, height: mouse.y - start.mouse.y)
        window.setFrameOrigin(CGPoint(
            x: start.window.minX + offset.width,
            y: start.window.minY + offset.height
        ))
        if ended {
            overlayDragStart = nil
            positionToolbar()
            constrainWindowGroupToVisibleFrame()
        }
    }

    private func constrainWindowGroupToVisibleFrame() {
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame
        let frames = [window.frame, toolbarWindow.frame] + (comparisonWindow.map { [$0.frame] } ?? [])
        let group = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        var offset = CGSize.zero
        if group.minX < visibleFrame.minX { offset.width = visibleFrame.minX - group.minX }
        if group.maxX > visibleFrame.maxX { offset.width = visibleFrame.maxX - group.maxX }
        if group.minY < visibleFrame.minY { offset.height = visibleFrame.minY - group.minY }
        if group.maxY > visibleFrame.maxY { offset.height = visibleFrame.maxY - group.maxY }
        guard offset != .zero else { return }
        window.setFrameOrigin(CGPoint(x: window.frame.minX + offset.width, y: window.frame.minY + offset.height))
    }

    private func toggleComparison() {
        if let comparisonWindow {
            window.removeChildWindow(comparisonWindow)
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
            styleMask: Self.auxiliaryOverlayStyleMask,
            backing: .buffered,
            defer: false
        )
        configure(panel: original, title: "截图翻译原文对照", shadow: true)
        original.onEscape = { [weak self] in self?.close() }
        original.contentView = ScreenshotTranslationFirstMouseHostingView(
            rootView: ScreenshotOriginalImageView(image: model.image)
        )
        comparisonWindow = original
        model.comparisonEnabled = true
        window.setFrame(frames.translated, display: true)
        window.addChildWindow(original, ordered: .below)
        original.orderFrontRegardless()
        window.orderFrontRegardless()
        toolbarWindow.orderFrontRegardless()
        positionToolbar()
        window.makeKey()
    }

    private func installInputMonitors() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.window.isVisible == true else { return event }
            self?.close()
            return nil
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self,
                  self.window.isVisible,
                  let eventWindow = event.window,
                  eventWindow === self.window || eventWindow === self.comparisonWindow else {
                return event
            }
            self.overlayDragStart = nil
            let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
            self.scaleOverlay(
                by: max(0.1, 1 + event.magnification),
                around: screenPoint
            )
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

private final class ScreenshotTranslationFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct ScreenshotOriginalImageView: View {
    let image: CGImage

    var body: some View {
        GeometryReader { proxy in
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}

struct ScreenshotTranslationOverlayView: View {
    @ObservedObject var model: ScreenshotTranslationOverlayModel
    @ObservedObject var store: TranslationEditorStore
    let dragToPointer: (Bool) -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        GeometryReader { proxy in
            translationLayer(size: proxy.size)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in dragToPointer(false) }
                    .onEnded { _ in dragToPointer(true) }
            )
        }
        .task(id: translationRequestID) {
            guard !store.editableSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await requestTranslation()
        }
        .translationTask(configuration) { session in
            await store.performLineTranslations(
                using: session,
                sourceLines: ScreenshotTranslationOverlayWindowController.translatableSentences(regions: model.regions)
            )
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
            let layout = ScreenshotTranslationOverlayWindowController.displayLayout(
                from: sourceBlocks,
                in: size
            )
            ScreenshotTranslationCanvasView(
                image: model.image,
                layout: layout,
                viewportSize: size
            )
        }
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
        let sourceLines = ScreenshotTranslationOverlayWindowController.translatableSentences(regions: model.regions)
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

private struct ScreenshotTranslationCanvasView: View {
    let image: CGImage
    let layout: ScreenshotTranslationLayout
    let viewportSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                .allowsHitTesting(false)

            ForEach(layout.blocks) { block in
                coveragePatch(block)
            }

            ForEach(layout.blocks) { block in
                translatedBlock(block)
            }
        }
        .frame(
            width: layout.canvasSize.width,
            height: layout.canvasSize.height,
            alignment: .topLeading
        )
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        .clipped()
    }

    private func coveragePatch(_ block: ScreenshotTranslationDisplayBlock) -> some View {
        blockBackground(block.backgroundColor)
            .frame(
                width: max(block.coverageFrame.width, 1),
                height: max(block.coverageFrame.height, 1)
            )
            .position(
                x: block.coverageFrame.midX,
                y: block.coverageFrame.midY
            )
    }

    private func translatedBlock(_ block: ScreenshotTranslationDisplayBlock) -> some View {
        Text(block.text)
            .font(.system(size: block.fontSize, weight: .regular))
            .foregroundStyle(block.backgroundColor.isDark ? Color.white : Color.black)
            .lineSpacing(block.lineSpacing)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .frame(
                width: max(block.frame.width, 1),
                height: max(block.frame.height, 1),
                alignment: .leading
            )
            .background(blockBackground(block.backgroundColor))
            .shadow(
                color: block.backgroundColor.variation > 0.08
                    ? (block.backgroundColor.isDark ? .black.opacity(0.7) : .white.opacity(0.8))
                    : .clear,
                radius: 0.7
            )
            .position(x: block.frame.midX, y: block.frame.midY)
    }

    @ViewBuilder
    private func blockBackground(_ color: OCRBackgroundColor) -> some View {
        if color.variation > 0.08 {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Color(red: color.red, green: color.green, blue: color.blue)
                        .opacity(0.58)
                )
        } else {
            Color(red: color.red, green: color.green, blue: color.blue)
                .opacity(1)
        }
    }
}

private struct ScreenshotTranslationToolbarView: View {
    @ObservedObject var model: ScreenshotTranslationOverlayModel
    @ObservedObject var store: TranslationEditorStore
    let dragToPointer: (Bool) -> Void
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let toggleComparison: () -> Void
    let close: () -> Void
    @GestureState private var isDragging = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
                .padding(5)
                .background(
                    isDragging ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.055),
                    in: Circle()
                )
                .scaleEffect(isDragging ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: isDragging)
                .help(isDragging ? "正在移动截图翻译窗口" : "按住拖动截图翻译窗口")
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { _ in dragToPointer(false) }
                    .onEnded { _ in dragToPointer(true) }
                    .updating($isDragging) { _, state, _ in state = true })
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("缩小译图内容")
            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("放大译图内容")
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
        .frame(width: 224, height: 40)
        .background(.ultraThickMaterial, in: Capsule())
    }
}
