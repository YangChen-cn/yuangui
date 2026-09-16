import AppKit

extension ScreenshotAnnotation {
    var tool: ScreenshotTool {
        switch self {
        case let .stroke(_, _, _, highlighter): highlighter ? .highlighter : .pen
        case let .line(_, _, _, _, arrow): arrow ? .arrow : .line
        case let .rectangle(_, _, _, ellipse): ellipse ? .ellipse : .rectangle
        case .text: .text
        case .marker: .marker
        case .mosaic: .mosaic
        case .blur: .blur
        }
    }
    var editingStyle: AnnotationStyle? {
        switch self {
        case let .stroke(_, _, style, highlighter):
            var result = style
            if highlighter { result.color = style.color.withAlphaComponent(1); result.lineWidth /= 2.4 }
            return result
        case let .line(_, _, _, style, _), let .rectangle(_, _, style, _), let .text(_, _, _, style), let .marker(_, _, _, style): return style
        case let .mosaic(_, _, width): return AnnotationStyle(color: .systemRed, lineWidth: width / 3, fontSize: 28)
        case .blur: return nil
        }
    }
    func contains(_ point: CGPoint, tolerance: CGFloat = 5) -> Bool {
        func near(_ points: [CGPoint], radius: CGFloat) -> Bool {
            guard let first = points.first else { return false }
            if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= radius }
            for (a, b) in zip(points, points.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = dx * dx + dy * dy
                let t = length == 0 ? 0 : min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
                if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= radius { return true }
            }
            return false
        }
        switch self {
        case let .stroke(_, points, style, _): return near(points, radius: style.lineWidth / 2 + tolerance)
        case let .line(_, start, end, style, _): return near([start, end], radius: style.lineWidth / 2 + tolerance)
        case let .mosaic(_, points, width): return near(points, radius: width / 2 + tolerance)
        default: return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    var bounds: CGRect {
        switch self {
        case let .stroke(_, points, style, _): return Self.pointBounds(points).insetBy(dx: -style.lineWidth / 2, dy: -style.lineWidth / 2)
        case let .mosaic(_, points, width): return Self.pointBounds(points).insetBy(dx: -width / 2, dy: -width / 2)
        case let .line(_, start, end, style, _): return Self.pointBounds([start, end]).insetBy(dx: -max(8, style.lineWidth), dy: -max(8, style.lineWidth))
        case let .rectangle(_, rect, _, _), let .blur(_, rect): return rect
        case let .text(_, origin, text, style): return CGRect(origin: origin, size: text.size(withAttributes: [.font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)]))
        case let .marker(_, center, _, style): return CGRect(x: center.x - style.fontSize * 0.7, y: center.y - style.fontSize * 0.7, width: style.fontSize * 1.4, height: style.fontSize * 1.4)
        }
    }
    private static func pointBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        let minX = points.map(\.x).min() ?? first.x, maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y, maxY = points.map(\.y).max() ?? first.y
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    func transformed(dx: CGFloat = 0, dy: CGFloat = 0, style replacement: AnnotationStyle? = nil) -> Self {
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        switch self {
        case let .stroke(id, points, style, highlighter):
            var updated = replacement ?? style
            if highlighter, replacement != nil { updated.color = updated.color.withAlphaComponent(0.34); updated.lineWidth = max(10, updated.lineWidth * 2.4) }
            return .stroke(id: id, points: points.map(point), style: updated, highlighter: highlighter)
        case let .line(id, start, end, style, arrow): return .line(id: id, start: point(start), end: point(end), style: replacement ?? style, arrow: arrow)
        case let .rectangle(id, rect, style, ellipse): return .rectangle(id: id, rect: rect.offsetBy(dx: dx, dy: dy), style: replacement ?? style, ellipse: ellipse)
        case let .text(id, origin, text, style): return .text(id: id, origin: point(origin), text: text, style: replacement ?? style)
        case let .mosaic(id, points, width): return .mosaic(id: id, points: points.map(point), width: replacement.map { max(18, $0.lineWidth * 3) } ?? width)
        case let .blur(id, rect): return .blur(id: id, rect: rect.offsetBy(dx: dx, dy: dy))
        case let .marker(id, center, number, style): return .marker(id: id, center: point(center), number: number, style: replacement ?? style)
        }
    }
}
