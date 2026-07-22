import Foundation

enum ScreenshotTranslationLineAligner {
    static func combinedText(for sourceLines: [String]) -> String {
        sourceLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in "[[\(String(format: "%04d", index))]] \(text)" }
            .joined(separator: "\n")
    }

    static func align(_ translatedText: String, to sourceLines: [String]) -> [String] {
        let sourceLines = sourceLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sourceLines.isEmpty else { return [] }
        if let marked = markedLines(from: translatedText, count: sourceLines.count) {
            return marked
        }
        let formatted = TranslationTextFormatter.addingSemanticLineBreaks(translatedText)
        let explicitLines = formatted.components(separatedBy: .newlines)
            .map(singleLine)
            .filter { !$0.isEmpty }
        if explicitLines.count == sourceLines.count { return explicitLines.map(removingMarkers) }
        return proportionalLines(from: removingMarkers(formatted), sourceLines: sourceLines)
    }

    private static func markedLines(from text: String, count: Int) -> [String]? {
        let pattern = #"[\[［]{1,2}\s*(\d{1,4})\s*[\]］]{1,2}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let value = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: value.length))
        guard !matches.isEmpty else { return nil }
        var mapped: [Int: String] = [:]
        for (offset, match) in matches.enumerated() {
            guard match.numberOfRanges > 1 else { continue }
            let identifier = Int(value.substring(with: match.range(at: 1)))
            let start = NSMaxRange(match.range)
            let end = offset + 1 < matches.count ? matches[offset + 1].range.location : value.length
            guard let identifier, identifier < count, end >= start else { continue }
            let content = value.substring(with: NSRange(location: start, length: end - start))
            mapped[identifier] = singleLine(removingMarkers(content))
        }
        guard mapped.count == count else { return nil }
        return (0..<count).map { mapped[$0] ?? "" }
    }

    private static func removingMarkers(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"[\[［]{1,2}\s*\d{1,4}\s*[\]］]{1,2}"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func proportionalLines(from text: String, sourceLines: [String]) -> [String] {
        let normalized = singleLine(text)
        let characters = Array(normalized)
        guard !characters.isEmpty else { return Array(repeating: "", count: sourceLines.count) }
        guard sourceLines.count > 1, characters.count >= sourceLines.count else {
            return [normalized] + Array(repeating: "", count: max(0, sourceLines.count - 1))
        }

        let weights = sourceLines.map { max(1, $0.count) }
        let totalWeight = max(1, weights.reduce(0, +))
        var consumedWeight = 0
        var start = 0
        var result: [String] = []
        for index in sourceLines.indices {
            guard index < sourceLines.count - 1 else {
                result.append(singleLine(String(characters[start...])))
                break
            }
            consumedWeight += weights[index]
            let desired = Int(
                (Double(consumedWeight) / Double(totalWeight) * Double(characters.count)).rounded()
            )
            let lower = start + 1
            let upper = characters.count - (sourceLines.count - index - 1)
            let boundary = bestBoundary(in: characters, desired: desired, lower: lower, upper: upper)
            result.append(singleLine(String(characters[start..<boundary])))
            start = boundary
        }
        return result
    }

    private static func bestBoundary(
        in characters: [Character],
        desired: Int,
        lower: Int,
        upper: Int
    ) -> Int {
        guard lower < upper else { return lower }
        let clampedDesired = min(max(desired, lower), upper)
        var best = clampedDesired
        var bestScore = Int.max
        for candidate in lower...upper {
            let previous = characters[candidate - 1]
            let next = candidate < characters.count ? characters[candidate] : " "
            let boundaryPenalty: Int
            if previous == "\n" || next == "•" || next == "▪" || next == "◦" {
                boundaryPenalty = 0
            } else if ".!?。！？;；:：".contains(previous) {
                boundaryPenalty = 2
            } else if previous.isWhitespace || next.isWhitespace {
                boundaryPenalty = 42
            } else {
                boundaryPenalty = 120
            }
            let score = abs(candidate - clampedDesired) + boundaryPenalty
            if score < bestScore {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
