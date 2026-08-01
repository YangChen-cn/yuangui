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
            VStack(alignment: .leading, spacing: 2) {
                if let message {
                    Text(AppLocalizer.string(message))
                }
                if let replacementHint {
                    Text(AppLocalizer.string(replacementHint))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)

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
}
