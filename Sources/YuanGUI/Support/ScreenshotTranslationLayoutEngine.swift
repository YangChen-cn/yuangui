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

    static func layout(
        blocks: [ScreenshotTranslationBlock],
        in size: CGSize
    ) -> ScreenshotTranslationLayout {
        guard size.width > 0, size.height > 0 else { return ScreenshotTranslationLayout(blocks: []) }
        let bounds = CGRect(origin: .zero, size: size)
        let anchors = blocks.map { clampedDisplayRect(for: $0.normalizedRect, in: size, bounds: bounds) }
        let displayBlocks = blocks.enumerated().map { index, block in
            let frame = readableFrame(for: index, anchors: anchors, bounds: bounds)
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
            return ScreenshotTranslationDisplayBlock(
                id: block.id,
                frame: frame,
                text: block.text,
                fontSize: fitting.fontSize,
                backgroundColor: block.backgroundColor,
                lineSpacing: max(1, fitting.fontSize * 0.15),
                usesOverflowCard: !fitting.fits
            )
        }
        return ScreenshotTranslationLayout(blocks: displayBlocks)
    }

    private static func fittingFontSize(
        for text: String,
        in size: CGSize,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> (fontSize: CGFloat, fits: Bool) {
        let available = CGSize(width: max(1, size.width - 8), height: max(1, size.height - 4))
        if measuredSize(text, fontSize: maximum, width: available.width).height <= available.height {
            return (maximum, true)
        }
        let minimumHeight = measuredSize(text, fontSize: minimum, width: available.width).height
        guard minimumHeight <= available.height else { return (minimum, false) }
        var lower = minimum
        var upper = maximum
        for _ in 0..<12 {
            let candidate = (lower + upper) / 2
            if measuredSize(text, fontSize: candidate, width: available.width).height <= available.height {
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
        return CGSize(width: ceil(measured.width), height: ceil(measured.height + fontSize * 0.12))
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
