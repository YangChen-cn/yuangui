import CoreGraphics
import Foundation

enum OCRLayoutAnalyzer {
    static func organize(_ regions: [OCRTextRegion]) -> OCRRecognition {
        let unique = deduplicated(regions)
        let ordered = readingOrder(unique)
        guard !ordered.isEmpty else { return OCRRecognition(regions: []) }

        var paragraph = 0
        var previous: OCRTextRegion?
        let laidOut = ordered.enumerated().map { index, region in
            if let previous, startsNewParagraph(previous: previous, current: region) {
                paragraph += 1
            }
            previous = region
            return region.assigningLayout(paragraphIndex: paragraph, readingOrder: index)
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
}
