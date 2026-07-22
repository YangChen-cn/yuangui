import CoreGraphics
import CoreText
import Foundation

struct ScreenshotTranslationLayout: Equatable, Sendable {
    let blocks: [ScreenshotTranslationDisplayBlock]

    var overflowBlocks: [ScreenshotTranslationDisplayBlock] {
        blocks.filter(\.usesOverflowCard)
    }
}

enum ScreenshotTranslationLayoutEngine {
    static let minimumReadableFontSize: CGFloat = 11
    static let minimumInPlaceFontSize: CGFloat = 7

    /// Layout used by the live screenshot overlay. Unlike the general-purpose solver, this
    /// deliberately never borrows whitespace, moves a block, or merges neighboring blocks.
    /// Every translated visual line stays on the exact OCR rectangle that produced it.
    static func inPlaceLayout(
        blocks: [ScreenshotTranslationBlock],
        in size: CGSize
    ) -> ScreenshotTranslationLayout {
        guard size.width > 0, size.height > 0 else { return ScreenshotTranslationLayout(blocks: []) }
        let bounds = CGRect(origin: .zero, size: size)
        let displayBlocks = blocks.map { block in
            let frame = clampedDisplayRect(for: block.normalizedRect, in: size, bounds: bounds)
            let preferredMaximum = min(
                40,
                max(minimumInPlaceFontSize, block.sourceFontScale * size.height * 0.94)
            )
            let fitting = fittingFontSize(
                for: block.text,
                in: frame.size,
                minimum: minimumInPlaceFontSize,
                maximum: preferredMaximum
            )
            return displayBlock(
                source: block,
                frame: frame,
                fontSize: fitting.fontSize,
                usesOverflowCard: false
            )
        }
        return ScreenshotTranslationLayout(blocks: displayBlocks)
    }

    static func layout(
        blocks: [ScreenshotTranslationBlock],
        in size: CGSize
    ) -> ScreenshotTranslationLayout {
        guard size.width > 0, size.height > 0 else { return ScreenshotTranslationLayout(blocks: []) }
        let bounds = CGRect(origin: .zero, size: size)
        let anchors = blocks.map { clampedDisplayRect(for: $0.normalizedRect, in: size, bounds: bounds) }
        let displayBlocks = blocks.enumerated().map { index, block in
            var frame = readableFrame(for: index, anchors: anchors, bounds: bounds)
            let preferredMaximum = min(
                40,
                max(16, block.sourceFontScale * size.height * 0.94)
            )
            let fitting = fittingFontSize(
                for: block.text,
                in: frame.size,
                minimum: minimumReadableFontSize,
                maximum: preferredMaximum
            )
            var fontSize = fitting.fontSize
            var candidate = displayBlock(
                source: block,
                frame: frame,
                fontSize: fontSize,
                usesOverflowCard: false
            )
            while fontSize > minimumReadableFontSize, !textFits(candidate) {
                fontSize = max(minimumReadableFontSize, floor((fontSize - 0.5) * 10) / 10)
                candidate = displayBlock(
                    source: block,
                    frame: frame,
                    fontSize: fontSize,
                    usesOverflowCard: false
                )
            }
            let fitsCurrentSlot = textFits(candidate)
            let requiredHeight = measuredSize(
                block.text,
                fontSize: fitsCurrentSlot ? fontSize : minimumReadableFontSize,
                width: max(1, frame.width - 8)
            ).height + 4
            if fitsCurrentSlot {
                frame = tightenedFrame(frame, around: anchors[index].midY, requiredHeight: requiredHeight)
            } else {
                frame = expandedFrame(
                    frame,
                    around: anchors[index].midY,
                    requiredHeight: requiredHeight,
                    bounds: bounds
                )
                fontSize = minimumReadableFontSize
            }
            return displayBlock(
                source: block,
                frame: frame,
                fontSize: fontSize,
                usesOverflowCard: false
            )
        }
        let resolved = resolveOverlaps(displayBlocks, bounds: bounds)
        return ScreenshotTranslationLayout(blocks: mergeResidualOverlaps(resolved, bounds: bounds))
    }

    static func textFits(_ block: ScreenshotTranslationDisplayBlock) -> Bool {
        measuredSize(
            block.text,
            fontSize: block.fontSize,
            width: max(1, block.frame.width - 8)
        ).height <= max(1, block.frame.height - 4)
    }

    private static func displayBlock(
        source: ScreenshotTranslationBlock,
        frame: CGRect,
        fontSize: CGFloat,
        usesOverflowCard: Bool
    ) -> ScreenshotTranslationDisplayBlock {
        ScreenshotTranslationDisplayBlock(
            id: source.id,
            frame: frame,
            text: source.text,
            fontSize: fontSize,
            backgroundColor: source.backgroundColor,
            lineSpacing: 0,
            usesOverflowCard: usesOverflowCard
        )
    }

    private static func expandedFrame(
        _ frame: CGRect,
        around anchorY: CGFloat,
        requiredHeight: CGFloat,
        bounds: CGRect
    ) -> CGRect {
        let height = min(bounds.height, max(frame.height, requiredHeight))
        let proposedY = anchorY - height / 2
        let y = min(max(proposedY, bounds.minY), bounds.maxY - height)
        return CGRect(x: frame.minX, y: y, width: frame.width, height: height)
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

    private static func resolveOverlaps(
        _ blocks: [ScreenshotTranslationDisplayBlock],
        bounds: CGRect
    ) -> [ScreenshotTranslationDisplayBlock] {
        var result = blocks
        let spacing: CGFloat = 2
        for _ in 0..<6 {
            var changed = false
            let order = result.indices.sorted { result[$0].frame.minY < result[$1].frame.minY }
            for firstPosition in order.indices {
                for secondPosition in order.indices where secondPosition > firstPosition {
                    let firstIndex = order[firstPosition]
                    let secondIndex = order[secondPosition]
                    var first = result[firstIndex]
                    var second = result[secondIndex]
                    let horizontalOverlap = max(
                        0,
                        min(first.frame.maxX, second.frame.maxX) - max(first.frame.minX, second.frame.minX)
                    )
                    guard horizontalOverlap >= min(first.frame.width, second.frame.width) * 0.15 else { continue }
                    var collision = first.frame.maxY + spacing - second.frame.minY
                    guard collision > 0 else { continue }

                    let moveDown = min(collision, max(0, bounds.maxY - second.frame.maxY))
                    if moveDown > 0 {
                        second = replacingFrame(second, second.frame.offsetBy(dx: 0, dy: moveDown))
                        result[secondIndex] = second
                        collision -= moveDown
                        changed = true
                    }
                    let moveUp = min(collision, max(0, first.frame.minY - bounds.minY))
                    if moveUp > 0 {
                        first = replacingFrame(first, first.frame.offsetBy(dx: 0, dy: -moveUp))
                        result[firstIndex] = first
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return result
    }

    /// Dense screenshots can be geometrically impossible to lay out as independent 11 pt boxes.
    /// Keep every translation on the screenshot by folding only the boxes that still collide
    /// after normal placement into one in-place multiline region. This replaces the old detached
    /// overflow card without hiding translated content or drawing two text layers on top of each other.
    private static func mergeResidualOverlaps(
        _ blocks: [ScreenshotTranslationDisplayBlock],
        bounds: CGRect
    ) -> [ScreenshotTranslationDisplayBlock] {
        var result = blocks
        while let pair = firstOverlappingPair(in: result) {
            let first = result[pair.0]
            let second = result[pair.1]
            var frame = first.frame.union(second.frame).intersection(bounds)
            let text = [first.text, second.text]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            let requiredHeight = measuredSize(
                text,
                fontSize: minimumReadableFontSize,
                width: max(1, frame.width - 8)
            ).height + 4
            frame = expandedFrame(
                frame,
                around: frame.midY,
                requiredHeight: requiredHeight,
                bounds: bounds
            )
            let merged = ScreenshotTranslationDisplayBlock(
                id: min(first.id, second.id),
                frame: frame,
                text: text,
                fontSize: minimumReadableFontSize,
                backgroundColor: first.backgroundColor,
                lineSpacing: 0,
                usesOverflowCard: false
            )
            result.remove(at: pair.1)
            result.remove(at: pair.0)
            result.append(merged)
            result = resolveOverlaps(result, bounds: bounds)
        }
        return result.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 0.5 { return lhs.frame.minY < rhs.frame.minY }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    private static func firstOverlappingPair(
        in blocks: [ScreenshotTranslationDisplayBlock]
    ) -> (Int, Int)? {
        guard blocks.count > 1 else { return nil }
        for first in blocks.indices {
            for second in blocks.indices where second > first {
                let intersection = blocks[first].frame.intersection(blocks[second].frame)
                if !intersection.isNull, intersection.width > 0.01, intersection.height > 0.01 {
                    return (first, second)
                }
            }
        }
        return nil
    }

    private static func replacingFrame(
        _ block: ScreenshotTranslationDisplayBlock,
        _ frame: CGRect
    ) -> ScreenshotTranslationDisplayBlock {
        ScreenshotTranslationDisplayBlock(
            id: block.id,
            frame: frame,
            text: block.text,
            fontSize: block.fontSize,
            backgroundColor: block.backgroundColor,
            lineSpacing: block.lineSpacing,
            usesOverflowCard: false
        )
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
        for _ in 0..<12 {
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

    private static func readableFrame(
        for index: Int,
        anchors: [CGRect],
        bounds: CGRect
    ) -> CGRect {
        let anchor = anchors[index]
        let relevant = anchors.enumerated().compactMap { candidateIndex, candidate -> (Int, CGRect)? in
            guard candidateIndex != index else { return nil }
            let overlap = max(0, min(anchor.maxX, candidate.maxX) - max(anchor.minX, candidate.minX))
            guard overlap >= min(anchor.width, candidate.width) * 0.2 else { return nil }
            return (candidateIndex, candidate)
        }
        let previous = relevant
            .filter { candidateIndex, candidate in
                candidate.midY < anchor.midY
                    || (abs(candidate.midY - anchor.midY) < 0.5 && candidateIndex < index)
            }
            .max { $0.1.midY < $1.1.midY }
        let next = relevant
            .filter { candidateIndex, candidate in
                candidate.midY > anchor.midY
                    || (abs(candidate.midY - anchor.midY) < 0.5 && candidateIndex > index)
            }
            .min { $0.1.midY < $1.1.midY }
        let separation: CGFloat = 2
        let slotTop = previous.map { ($0.1.midY + anchor.midY) / 2 + separation / 2 } ?? bounds.minY
        let slotBottom = next.map { (anchor.midY + $0.1.midY) / 2 - separation / 2 } ?? bounds.maxY
        let top = min(max(slotTop, bounds.minY), bounds.maxY - 1)
        let bottom = max(min(slotBottom, bounds.maxY), top + 1)
        return CGRect(
            x: anchor.minX,
            y: top,
            width: anchor.width,
            height: max(1, bottom - top)
        ).intersection(bounds)
    }
}
