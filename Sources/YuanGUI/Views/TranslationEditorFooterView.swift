import SwiftUI

struct TranslationEditorFooterView: View {
    let message: String?
    let replacementHint: String?
    let canCopy: Bool
    let canReplace: Bool
    let targetCanReplace: Bool
    let close: () -> Void
    let copy: () -> Void
    let replace: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(statusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    TranslationMascotRole.source.accent.opacity(0.07),
                    in: Capsule()
                )

            Spacer(minLength: 8)

            Button("关闭", action: close)
                .keyboardShortcut(.cancelAction)
            Button("复制", action: copy)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!canCopy)
            Button("替换原文", action: replace)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canReplace)
                .help(targetCanReplace ? "把最新译文写回原应用的原选区" : "原位置不可编辑")
        }
        .controlSize(.small)
    }

    private var statusText: String {
        if let message { return AppLocalizer.string(message) }
        if let replacementHint { return AppLocalizer.string(replacementHint) }
        return AppLocalizer.string("translation.footer.ready")
    }

    private var statusIcon: String {
        message == nil ? "heart.text.square" : "bubble.left.fill"
    }
}
