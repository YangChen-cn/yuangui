import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let binding: HotKeyBinding
    let onChange: (HotKeyBinding) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.binding = binding
        view.onChange = context.coordinator.onChange
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.binding = binding
        nsView.onChange = context.coordinator.onChange
        nsView.needsDisplay = true
    }

    final class Coordinator {
        let onChange: (HotKeyBinding) -> Void
        init(onChange: @escaping (HotKeyBinding) -> Void) { self.onChange = onChange }
    }
}

final class ShortcutRecorderNSView: NSView {
    var binding = HotKeyBinding.screenshotDefault
    var onChange: ((HotKeyBinding) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 126, height: 28) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
            return
        }
        let modifiers = HotKeyModifiers(eventFlags: event.modifierFlags)
        let label = Self.keyLabel(for: event)
        guard !label.isEmpty else { NSSound.beep(); return }
        let newBinding = HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        guard newBinding.validationMessage == nil else { NSSound.beep(); return }
        binding = newBinding
        isRecording = false
        onChange?(newBinding)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text = isRecording ? "请按快捷键…" : binding.displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: "↩"
        case 48: "⇥"
        case 49: "Space"
        case 51: "⌫"
        case 53: "Esc"
        case 115: "Home"
        case 116: "Page Up"
        case 117: "⌦"
        case 119: "End"
        case 121: "Page Down"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
    }
}
