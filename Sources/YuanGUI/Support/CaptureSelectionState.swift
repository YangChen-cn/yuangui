import CoreGraphics

/// Pure geometry: dragging updates only this value and the AppKit overlay.
struct CaptureSelectionState {
    enum Phase: Equatable { case idle, dragging, selected, adjusting, committed }
    enum Handle: CaseIterable {
        case nw, n, ne, w, e, sw, s, se
        var x: CGFloat { switch self { case .nw, .w, .sw: -1; case .ne, .e, .se: 1; default: 0 } }
        var y: CGFloat { switch self { case .nw, .n, .ne: 1; case .sw, .s, .se: -1; default: 0 } }
        func point(in rect: CGRect) -> CGPoint { CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2) }
    }
    private(set) var phase: Phase = .idle
    private(set) var rect: CGRect = .zero
    private var anchor = CGPoint.zero
    private var initial = CGRect.zero
    private var handle: Handle?
    private var moving = false
    private var squareLocked = false

    var hasSelection: Bool { rect.width >= 3 && rect.height >= 3 }
    mutating func reset() { self = Self() }
    mutating func select(_ value: CGRect, within bounds: CGRect) {
        rect = value.intersection(bounds)
        phase = hasSelection ? .selected : .idle
    }
    func hitHandle(_ point: CGPoint) -> Handle? {
        guard hasSelection else { return nil }
        if let corner = Handle.allCases.first(where: { h in
            let p = h.point(in: rect)
            return abs(p.x - point.x) <= 7 && abs(p.y - point.y) <= 7
        }) { return corner }
        guard rect.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
        if abs(point.x - rect.minX) <= 6 { return .w }
        if abs(point.x - rect.maxX) <= 6 { return .e }
        if abs(point.y - rect.minY) <= 6 { return .s }
        if abs(point.y - rect.maxY) <= 6 { return .n }
        return nil
    }
    mutating func begin(at point: CGPoint) {
        guard phase != .committed else { return }
        anchor = point
        squareLocked = false
        initial = rect
        handle = hitHandle(point)
        moving = handle == nil && hasSelection && rect.contains(point)
        if handle != nil || moving { phase = .adjusting }
        else { rect = CGRect(origin: point, size: .zero); phase = .dragging }
    }
    mutating func drag(to point: CGPoint, within bounds: CGRect, square: Bool = false, centered: Bool = false) {
        let point = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        if phase == .dragging {
            // Keep the chosen constraint through modifier release and the final mouse-up.
            squareLocked = squareLocked || square
            var end = point
            if squareLocked {
                let side = min(abs(dx), abs(dy))
                end = CGPoint(x: anchor.x + (dx < 0 ? -side : side), y: anchor.y + (dy < 0 ? -side : side))
            }
            rect = CGRect(x: min(anchor.x, end.x), y: min(anchor.y, end.y), width: abs(end.x - anchor.x), height: abs(end.y - anchor.y))
        } else if phase == .adjusting, moving {
            rect.origin = CGPoint(x: min(max(initial.minX + dx, bounds.minX), bounds.maxX - initial.width),
                                  y: min(max(initial.minY + dy, bounds.minY), bounds.maxY - initial.height))
        } else if phase == .adjusting, let handle {
            if centered {
                let halfWidth = min(max(1.5, initial.width / 2 + dx * handle.x), min(initial.midX - bounds.minX, bounds.maxX - initial.midX))
                let halfHeight = min(max(1.5, initial.height / 2 + dy * handle.y), min(initial.midY - bounds.minY, bounds.maxY - initial.midY))
                rect = CGRect(x: initial.midX - halfWidth, y: initial.midY - halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
                return
            }
            var left = initial.minX, right = initial.maxX, bottom = initial.minY, top = initial.maxY
            if handle.x < 0 { left = min(right - 3, left + dx) }
            if handle.x > 0 { right = max(left + 3, right + dx) }
            if handle.y < 0 { bottom = min(top - 3, bottom + dy) }
            if handle.y > 0 { top = max(bottom + 3, top + dy) }
            rect = CGRect(x: left, y: bottom, width: right - left, height: top - bottom).intersection(bounds)
        }
    }
    mutating func end() { if phase != .committed { phase = hasSelection ? .selected : .idle } }
    mutating func nudge(dx: CGFloat, dy: CGFloat, resize: Bool, within bounds: CGRect) {
        guard phase == .selected else { return }
        if resize {
            rect.size.width = min(max(3, rect.width + dx), bounds.maxX - rect.minX)
            rect.size.height = min(max(3, rect.height + dy), bounds.maxY - rect.minY)
        } else {
            rect.origin.x = min(max(rect.minX + dx, bounds.minX), bounds.maxX - rect.width)
            rect.origin.y = min(max(rect.minY + dy, bounds.minY), bounds.maxY - rect.height)
        }
    }
    mutating func commit() -> CGRect? {
        guard phase == .selected, hasSelection else { return nil }
        phase = .committed
        return rect
    }
}

enum CaptureMode: String, CaseIterable { case region, window, screen }
enum CaptureAction: String, CaseIterable { case quickAccess, copy, edit, ocr, translate, pin, save, confirm }

struct CaptureWindowTarget { let id: CGWindowID; let frame: CGRect }
