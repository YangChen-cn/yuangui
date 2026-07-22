import CoreGraphics
import Foundation

enum OCRLayoutAnalyzer {
    private struct PositionedRegion {
        let region: OCRTextRegion
        let columnIndex: Int
    }

    static func organize(_ regions: [OCRTextRegion]) -> OCRRecognition {
        let unique = deduplicated(regions)
        let ordered = positionedReadingOrder(unique)
        guard !ordered.isEmpty else { return OCRRecognition(regions: []) }

        let medianFontScale = median(ordered.map { $0.region.estimatedFontScale })
        var paragraph = 0
        var previous: PositionedRegion?
        let laidOut = ordered.enumerated().map { index, positioned in
            let region = positioned.region
            if let previous,
               previous.columnIndex != positioned.columnIndex
                || startsNewParagraph(previous: previous.region, current: region) {
                paragraph += 1
            }
            previous = positioned
            return region.assigningLayout(
                paragraphIndex: paragraph,
                columnIndex: positioned.columnIndex,
                readingOrder: index,
                role: role(for: region, medianFontScale: medianFontScale)
            )
        }
        return OCRRecognition(regions: laidOut)
    }

    static func deduplicated(_ regions: [OCRTextRegion]) -> [OCRTextRegion] {
        var kept: [OCRTextRegion] = []
        for candidate in regions.sorted(by: { $0.confidence > $1.confidence }) {
            let duplicate = kept.contains { existing in
                let overlap = intersectionRatio(candidate.normalizedRect, existing.normalizedRect)
                guard overlap >= 0.62 else { return false }
                let lhs = normalized(candidate.text)
                let rhs = normalized(existing.text)
                return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) || overlap >= 0.9
            }
            if !duplicate { kept.append(candidate) }
        }
        return kept
    }

    static func readingOrder(_ regions: [OCRTextRegion]) -> [OCRTextRegion] {
        positionedReadingOrder(regions).map(\.region)
    }

    private static func positionedReadingOrder(_ regions: [OCRTextRegion]) -> [PositionedRegion] {
        guard let split = columnSplit(in: regions) else {
            return rowOrdered(regions).map { PositionedRegion(region: $0, columnIndex: 0) }
        }
        let spanning = regions.filter { $0.normalizedRect.minX < split && $0.normalizedRect.maxX > split }
        let columnRegions = regions.filter { !spanning.contains($0) }
        let left = columnRegions.filter { $0.normalizedRect.midX < split }
        let right = columnRegions.filter { $0.normalizedRect.midX >= split }
        guard left.count >= 2, right.count >= 2 else {
            return rowOrdered(regions).map { PositionedRegion(region: $0, columnIndex: 0) }
        }
        let columnsTop = max(left.map { $0.normalizedRect.maxY }.max() ?? 0, right.map { $0.normalizedRect.maxY }.max() ?? 0)
        let columnsBottom = min(left.map { $0.normalizedRect.minY }.min() ?? 1, right.map { $0.normalizedRect.minY }.min() ?? 1)
        let topSpanning = spanning.filter { $0.normalizedRect.midY >= columnsTop - $0.normalizedRect.height }
        let bottomSpanning = spanning.filter { $0.normalizedRect.midY <= columnsBottom + $0.normalizedRect.height }
        let middleSpanning = spanning.filter { !topSpanning.contains($0) && !bottomSpanning.contains($0) }
        guard middleSpanning.isEmpty else {
            return rowOrdered(regions).map { PositionedRegion(region: $0, columnIndex: 0) }
        }
        return rowOrdered(topSpanning).map { PositionedRegion(region: $0, columnIndex: 0) }
            + rowOrdered(left).map { PositionedRegion(region: $0, columnIndex: 0) }
            + rowOrdered(right).map { PositionedRegion(region: $0, columnIndex: 1) }
            + rowOrdered(bottomSpanning).map { PositionedRegion(region: $0, columnIndex: 0) }
    }

    private static func rowOrdered(_ regions: [OCRTextRegion]) -> [OCRTextRegion] {
        var rows: [[OCRTextRegion]] = []
        for region in regions.sorted(by: topBefore) {
            if let index = rows.indices.min(by: {
                rowDistance(region, rows[$0]) < rowDistance(region, rows[$1])
            }), rowDistance(region, rows[index]) <= rowTolerance(region, rows[index]) {
                rows[index].append(region)
            } else {
                rows.append([region])
            }
        }
        rows.sort { rowTop($0) > rowTop($1) }
        return rows.flatMap { $0.sorted { $0.normalizedRect.minX < $1.normalizedRect.minX } }
    }

    private static func columnSplit(in regions: [OCRTextRegion]) -> CGFloat? {
        guard regions.count >= 4 else { return nil }
        // Full-width titles and footers must not pull the split toward one column.
        let columnCandidates = regions.filter { $0.normalizedRect.width < 0.6 }
        let centers = columnCandidates.map { $0.normalizedRect.midX }.sorted()
        guard centers.count >= 4 else { return nil }
        let candidates = zip(centers, centers.dropFirst()).enumerated().map { index, pair in
            (index: index, gap: pair.1 - pair.0, split: (pair.0 + pair.1) / 2)
        }
        guard let best = candidates.max(by: { $0.gap < $1.gap }), best.gap >= 0.12 else { return nil }
        let leftCount = best.index + 1
        let rightCount = centers.count - leftCount
        guard leftCount >= 2, rightCount >= 2 else { return nil }
        let left = columnCandidates.filter { $0.normalizedRect.midX < best.split }
        let right = columnCandidates.filter { $0.normalizedRect.midX >= best.split }
        let leftVertical = verticalExtent(left)
        let rightVertical = verticalExtent(right)
        let overlap = max(0, min(leftVertical.maxY, rightVertical.maxY) - max(leftVertical.minY, rightVertical.minY))
        guard overlap >= min(leftVertical.height, rightVertical.height) * 0.25 else { return nil }
        return best.split
    }

    private static func verticalExtent(_ regions: [OCRTextRegion]) -> CGRect {
        regions.dropFirst().reduce(regions.first?.normalizedRect ?? .zero) { $0.union($1.normalizedRect) }
    }

    private static func role(for region: OCRTextRegion, medianFontScale: CGFloat) -> OCRTextRole {
        if region.isProtectedText { return .protectedContent }
        let text = region.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^(?:[-*•▪◦]|\d+[.)、])\s*"#, options: .regularExpression) != nil {
            return .listItem
        }
        if medianFontScale > 0, region.estimatedFontScale >= medianFontScale * 1.35, text.count <= 100 {
            return .title
        }
        return .body
    }

    private static func startsNewParagraph(previous: OCRTextRegion, current: OCRTextRegion) -> Bool {
        let previousRect = previous.normalizedRect
        let currentRect = current.normalizedRect
        let sameVisualRow = abs(previousRect.midY - currentRect.midY)
            <= max(previousRect.height, currentRect.height) * 0.55
        if sameVisualRow { return false }
        let verticalGap = max(0, previousRect.minY - currentRect.maxY)
        let allowedGap = max(previousRect.height, currentRect.height) * 0.95
        let overlap = horizontalOverlap(previousRect, currentRect)
        let aligned = abs(previousRect.minX - currentRect.minX) <= 0.075
        return verticalGap > allowedGap || (!aligned && overlap < min(previousRect.width, currentRect.width) * 0.2)
    }

    private static func topBefore(_ lhs: OCRTextRegion, _ rhs: OCRTextRegion) -> Bool {
        if abs(lhs.normalizedRect.midY - rhs.normalizedRect.midY) > max(lhs.normalizedRect.height, rhs.normalizedRect.height) * 0.45 {
            return lhs.normalizedRect.midY > rhs.normalizedRect.midY
        }
        return lhs.normalizedRect.minX < rhs.normalizedRect.minX
    }

    private static func rowDistance(_ region: OCRTextRegion, _ row: [OCRTextRegion]) -> CGFloat {
        abs(region.normalizedRect.midY - row.map { $0.normalizedRect.midY }.reduce(0, +) / CGFloat(max(1, row.count)))
    }

    private static func rowTolerance(_ region: OCRTextRegion, _ row: [OCRTextRegion]) -> CGFloat {
        max(region.normalizedRect.height, row.map { $0.normalizedRect.height }.max() ?? 0) * 0.48
    }

    private static func rowTop(_ row: [OCRTextRegion]) -> CGFloat {
        row.map { $0.normalizedRect.midY }.reduce(0, +) / CGFloat(max(1, row.count))
    }

    private static func intersectionRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        return smallerArea > 0 ? intersection.width * intersection.height / smallerArea : 0
    }

    private static func horizontalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
