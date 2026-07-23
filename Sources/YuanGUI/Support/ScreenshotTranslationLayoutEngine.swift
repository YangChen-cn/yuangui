import CoreGraphics
import CoreText
import Foundation

struct ScreenshotTranslationLayout: Equatable, Sendable {
    let blocks: [ScreenshotTranslationDisplayBlock]
    let canvasSize: CGSize
    let requiredScale: CGFloat

    var overflowBlocks: [ScreenshotTranslationDisplayBlock] {
        blocks.filter(\.usesOverflowCard)
    }
}

enum ScreenshotTranslationLayoutEngine {
    static let minimumReadableFontSize: CGFloat = 7
    static let minimumInPlaceFontSize = minimumReadableFontSize
    private static let maximumCanvasScale: CGFloat = 64
    private static let cache = ScreenshotLayoutCache()

    /// The only screenshot-translation layout path used by production and tests.
    /// Horizontal OCR anchors remain immutable. If the text cannot fit at 7 pt,
    /// the logical canvas grows uniformly until every independent block fits.
    static func layout(
        blocks: [ScreenshotTranslationBlock],
        in viewportSize: CGSize
    ) -> ScreenshotTranslationLayout {
        let key = ScreenshotLayoutCache.Key(blocks: blocks, viewportSize: viewportSize)
        if let cached = cache.value(for: key) { return cached }
        let result = calculateLayout(blocks: blocks, in: viewportSize)
        cache.insert(result, for: key)
        return result
    }

    private static func calculateLayout(
        blocks: [ScreenshotTranslationBlock],
        in viewportSize: CGSize
    ) -> ScreenshotTranslationLayout {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return ScreenshotTranslationLayout(
                blocks: [],
                canvasSize: .zero,
                requiredScale: 1
            )
        }
        guard !blocks.isEmpty else {
            return ScreenshotTranslationLayout(
                blocks: [],
                canvasSize: viewportSize,
                requiredScale: 1
            )
        }

        let initial = makeLayout(blocks: blocks, canvasSize: viewportSize)
        if isValid(initial) {
            return ScreenshotTranslationLayout(
                blocks: initial,
                canvasSize: viewportSize,
                requiredScale: 1
            )
        }

        var lower: CGFloat = 1
        var upper: CGFloat = 1.5
        var upperLayout = makeLayout(
            blocks: blocks,
            canvasSize: scaled(viewportSize, by: upper)
        )
        while upper < maximumCanvasScale, !isValid(upperLayout) {
            lower = upper
            upper = min(maximumCanvasScale, upper * 1.5)
            upperLayout = makeLayout(
                blocks: blocks,
                canvasSize: scaled(viewportSize, by: upper)
            )
        }

        if isValid(upperLayout) {
            for _ in 0..<7 {
                let candidate = (lower + upper) / 2
                let candidateLayout = makeLayout(
                    blocks: blocks,
                    canvasSize: scaled(viewportSize, by: candidate)
                )
                if isValid(candidateLayout) {
                    upper = candidate
                    upperLayout = candidateLayout
                } else {
                    lower = candidate
                }
            }
        }

        let canvasSize = scaled(viewportSize, by: upper)
        return ScreenshotTranslationLayout(
            blocks: upperLayout,
            canvasSize: canvasSize,
            requiredScale: upper
        )
    }

    static func textFits(_ block: ScreenshotTranslationDisplayBlock) -> Bool {
        measuredSize(
            block.text,
            fontSize: block.fontSize,
            width: max(1, block.frame.width - 8)
        ).height <= max(1, block.frame.height - 4)
    }

    private static func makeLayout(
        blocks: [ScreenshotTranslationBlock],
        canvasSize: CGSize
    ) -> [ScreenshotTranslationDisplayBlock] {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let originalAnchors = blocks.map {
            clampedDisplayRect(for: $0.normalizedRect, in: canvasSize, bounds: bounds)
        }
        let anchors = horizontallyExpandedAnchors(
            blocks: blocks,
            anchors: originalAnchors,
            bounds: bounds
        )
        let coverageFrames = sourceCoverageFrames(
            for: originalAnchors,
            bounds: bounds
        )
        let readableFrames = readableFrames(for: anchors, bounds: bounds)
        return blocks.enumerated().map { index, block in
            let anchor = anchors[index]
            let availableFrame = readableFrames[index]
            let preferredMaximum = min(
                40,
                max(16, block.sourceFontScale * canvasSize.height * 1.05)
            )
            let fitting = fittingFontSize(
                for: block.text,
                in: availableFrame.size,
                minimum: minimumReadableFontSize,
                maximum: preferredMaximum
            )
            let requiredHeight = measuredSize(
                block.text,
                fontSize: fitting.fontSize,
                width: max(1, availableFrame.width - 8)
            ).height + 4
            let frame = tightenedFrame(
                availableFrame,
                around: anchor.midY,
                requiredHeight: max(anchor.height, requiredHeight)
            )
            return ScreenshotTranslationDisplayBlock(
                id: block.id,
                frame: frame,
                coverageFrame: coverageFrames[index],
                text: block.text,
                fontSize: fitting.fontSize,
                backgroundColor: block.backgroundColor,
                lineSpacing: 0,
                usesOverflowCard: false
            )
        }
    }

    private static func isValid(_ blocks: [ScreenshotTranslationDisplayBlock]) -> Bool {
        guard blocks.allSatisfy(textFits) else { return false }
        for first in blocks.indices {
            for second in blocks.indices where second > first {
                let intersection = blocks[first].frame.intersection(blocks[second].frame)
                if !intersection.isNull,
                   intersection.width > 0.01,
                   intersection.height > 0.01 {
                    return false
                }
            }
        }
        return true
    }

    private static func scaled(_ size: CGSize, by scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func tightenedFrame(
        _ frame: CGRect,
        around anchorY: CGFloat,
        requiredHeight: CGFloat
    ) -> CGRect {
        let height = min(frame.height, max(1, requiredHeight))
        let y = min(max(anchorY - height / 2, frame.minY), frame.maxY - height)
        return CGRect(x: frame.minX, y: y, width: frame.width, height: height)
    }

    private static func fittingFontSize(
        for text: String,
        in size: CGSize,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> (fontSize: CGFloat, fits: Bool) {
        let available = CGSize(width: max(1, size.width - 8), height: max(1, size.height - 4))
        let safeHeight = max(1, available.height - 1.5)
        if measuredSize(text, fontSize: maximum, width: available.width).height <= safeHeight {
            return (maximum, true)
        }
        let minimumHeight = measuredSize(text, fontSize: minimum, width: available.width).height
        guard minimumHeight <= safeHeight else { return (minimum, false) }
        var lower = minimum
        var upper = maximum
        for _ in 0..<7 {
            let candidate = (lower + upper) / 2
            if measuredSize(text, fontSize: candidate, width: available.width).height <= safeHeight {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return (floor(lower * 10) / 10, true)
    }

    private static func measuredSize(_ text: String, fontSize: CGFloat, width: CGFloat) -> CGSize {
        guard let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) else { return .zero }
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: CFAttributedStringGetLength(attributed)),
            nil,
            CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            &fitRange
        )
        return CGSize(width: ceil(measured.width), height: ceil(measured.height + 1))
    }

    private static func clampedDisplayRect(
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

    /// Vision often returns a tight glyph box for short headings. Preserve the
    /// heading's left anchor, but let it use free space to the next item on the
    /// same visual row so words such as “Work” and “Reason” do not stack one
    /// character per line.
    private static func horizontallyExpandedAnchors(
        blocks: [ScreenshotTranslationBlock],
        anchors: [CGRect],
        bounds: CGRect
    ) -> [CGRect] {
        let gap = max(6, bounds.width * 0.008)

        return anchors.indices.map { index in
            let block = blocks[index]
            let anchor = anchors[index]
            let preferredFontSize = min(
                40,
                max(16, block.sourceFontScale * bounds.height * 1.05)
            )
            let oneLineWidth = measuredSize(
                block.text,
                fontSize: preferredFontSize,
                width: bounds.width
            ).width + 8
            // Expand only when the original OCR box would force avoidable
            // wrapping. This also covers headings that OCR classified as body.
            guard oneLineWidth > anchor.width + 1 else { return anchor }

            let nextPeerX = anchors.indices
                .filter { candidate in
                    guard candidate != index,
                          anchors[candidate].minX > anchor.minX else { return false }
                    let verticalOverlap = max(
                        0,
                        min(anchor.maxY, anchors[candidate].maxY)
                            - max(anchor.minY, anchors[candidate].minY)
                    )
                    return verticalOverlap >= min(anchor.height, anchors[candidate].height) * 0.25
                }
                .map { anchors[$0].minX }
                .min()
                ?? bounds.maxX
            let availableWidth = max(anchor.width, nextPeerX - gap - anchor.minX)
            let expandedWidth = min(availableWidth, max(anchor.width, oneLineWidth))
            return CGRect(
                x: anchor.minX,
                y: anchor.minY,
                width: min(expandedWidth, bounds.maxX - anchor.minX),
                height: anchor.height
            )
        }
    }

    /// Keep erasing the source at its original OCR position even when the
    /// translated frame moves. Vision boxes can be a little too tight around
    /// the first or last glyph, so expand horizontally without crossing the
    /// midpoint to another item on the same visual row.
    private static func sourceCoverageFrames(
        for anchors: [CGRect],
        bounds: CGRect
    ) -> [CGRect] {
        anchors.indices.map { index in
            let anchor = anchors[index]
            let rowPeers = anchors.indices.filter { candidate in
                guard candidate != index else { return false }
                let verticalOverlap = max(
                    0,
                    min(anchor.maxY, anchors[candidate].maxY)
                        - max(anchor.minY, anchors[candidate].minY)
                )
                return verticalOverlap >= min(anchor.height, anchors[candidate].height) * 0.25
            }
            let previous = rowPeers
                .map { anchors[$0] }
                .filter { $0.maxX <= anchor.minX }
                .max { $0.maxX < $1.maxX }
            let next = rowPeers
                .map { anchors[$0] }
                .filter { $0.minX >= anchor.maxX }
                .min { $0.minX < $1.minX }
            let leftLimit = previous.map { ($0.maxX + anchor.minX) / 2 } ?? bounds.minX
            let rightLimit = next.map { (anchor.maxX + $0.minX) / 2 } ?? bounds.maxX
            let horizontalMargin = max(3, anchor.height * 1.35)
            let verticalMargin = max(1, min(4, anchor.height * 0.12))
            let minX = max(leftLimit, anchor.minX - horizontalMargin)
            let maxX = min(rightLimit, anchor.maxX + horizontalMargin)
            let minY = max(bounds.minY, anchor.minY - verticalMargin)
            let maxY = min(bounds.maxY, anchor.maxY + verticalMargin)
            return CGRect(
                x: minX,
                y: minY,
                width: max(1, maxX - minX),
                height: max(1, maxY - minY)
            )
        }
    }

    private static func readableFrames(for anchors: [CGRect], bounds: CGRect) -> [CGRect] {
        var remaining = Set(anchors.indices)
        var result = anchors

        while let seed = remaining.first {
            var component: [Int] = []
            var pending = [seed]
            remaining.remove(seed)
            while let index = pending.popLast() {
                component.append(index)
                for candidate in Array(remaining)
                where horizontallyRelated(anchors[index], anchors[candidate]) {
                    remaining.remove(candidate)
                    pending.append(candidate)
                }
            }

            let ordered = component.sorted {
                let difference = anchors[$0].midY - anchors[$1].midY
                return abs(difference) > 0.5 ? difference < 0 : $0 < $1
            }
            let count = CGFloat(ordered.count)
            let minimumCenterGap = bounds.height / max(2, count * 2)
            var centers = Array(repeating: CGFloat.zero, count: ordered.count)
            for position in ordered.indices {
                let lower = bounds.minY + (CGFloat(position) + 0.5) * minimumCenterGap
                let upper = bounds.maxY
                    - (CGFloat(ordered.count - position) - 0.5) * minimumCenterGap
                let previousMinimum = position == 0
                    ? lower
                    : centers[position - 1] + minimumCenterGap
                centers[position] = min(
                    max(anchors[ordered[position]].midY, previousMinimum),
                    max(previousMinimum, upper)
                )
            }

            for position in ordered.indices {
                let index = ordered[position]
                let top = position == 0
                    ? bounds.minY
                    : (centers[position - 1] + centers[position]) / 2 + 1
                let bottom = position == ordered.count - 1
                    ? bounds.maxY
                    : (centers[position] + centers[position + 1]) / 2 - 1
                result[index] = CGRect(
                    x: anchors[index].minX,
                    y: top,
                    width: anchors[index].width,
                    height: max(1, bottom - top)
                ).intersection(bounds)
            }
        }
        return result
    }

    private static func horizontallyRelated(_ first: CGRect, _ second: CGRect) -> Bool {
        let overlap = max(0, min(first.maxX, second.maxX) - max(first.minX, second.minX))
        return overlap >= min(first.width, second.width) * 0.2
    }
}

private final class ScreenshotLayoutCache: @unchecked Sendable {
    struct Key: Hashable {
        struct Block: Hashable {
            let id: Int
            let x: CGFloat
            let y: CGFloat
            let width: CGFloat
            let height: CGFloat
            let text: String
            let sourceFontScale: CGFloat
            let role: String
            let red: Double
            let green: Double
            let blue: Double
            let variation: Double
        }

        let width: CGFloat
        let height: CGFloat
        let blocks: [Block]

        init(blocks: [ScreenshotTranslationBlock], viewportSize: CGSize) {
            width = viewportSize.width
            height = viewportSize.height
            self.blocks = blocks.map {
                Block(
                    id: $0.id,
                    x: $0.normalizedRect.minX,
                    y: $0.normalizedRect.minY,
                    width: $0.normalizedRect.width,
                    height: $0.normalizedRect.height,
                    text: $0.text,
                    sourceFontScale: $0.sourceFontScale,
                    role: $0.role.rawValue,
                    red: $0.backgroundColor.red,
                    green: $0.backgroundColor.green,
                    blue: $0.backgroundColor.blue,
                    variation: $0.backgroundColor.variation
                )
            }
        }
    }

    private let lock = NSLock()
    private var values: [Key: ScreenshotTranslationLayout] = [:]
    private var order: [Key] = []
    private let capacity = 64

    func value(for key: Key) -> ScreenshotTranslationLayout? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func insert(_ value: ScreenshotTranslationLayout, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        guard values[key] == nil else { return }
        values[key] = value
        order.append(key)
        if order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }
}
