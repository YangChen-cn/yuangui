import AppKit
import SwiftUI

/// A native text view that grows with its contents so the surrounding diary
/// page remains the only vertical scroll container.
struct DiaryGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let minimumHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .preferredFont(forTextStyle: .body)
        textView.defaultParagraphStyle = paragraphStyle
        textView.string = text
        textView.setAccessibilityLabel("日记正文")
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.text = $text
        if textView.string != text {
            textView.string = text
        }
        textView.font = .preferredFont(forTextStyle: .body)
        textView.defaultParagraphStyle = paragraphStyle
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: NSTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return nil
        }

        textView.frame.size.width = width
        textContainer.containerSize = NSSize(
            width: max(0, width - textView.textContainerInset.width * 2),
            height: .greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let contentHeight = layoutManager.usedRect(for: textContainer).height
            + textView.textContainerInset.height * 2
        return CGSize(width: width, height: max(minimumHeight, ceil(contentHeight)))
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        return style
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            textView.invalidateIntrinsicContentSize()
        }
    }
}

struct DiaryImagePasteCommandMonitor: NSViewRepresentable {
    let onPasteImage: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onPasteImage: onPasteImage)
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.onPasteImage = onPasteImage
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class MonitorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                coordinator?.uninstall()
            } else {
                coordinator?.install()
            }
        }
    }

    final class Coordinator {
        weak var view: MonitorView?
        var onPasteImage: () -> Bool
        private var eventMonitor: Any?

        init(onPasteImage: @escaping () -> Bool) {
            self.onPasteImage = onPasteImage
        }

        func install() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.window === view?.window,
                      !event.isARepeat,
                      event.charactersIgnoringModifiers?.lowercased() == "v",
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      onPasteImage() else {
                    return event
                }
                return nil
            }
        }

        func uninstall() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        deinit {
            uninstall()
        }
    }
}
