import SwiftUI

struct TranslationResultSection: View {
    let text: String
    let state: TranslationEditorStore.State
    let height: CGFloat
    let isSpeaking: Bool
    let canSpeak: Bool
    let canInstallShortcut: Bool
    let toggleSpeech: () -> Void
    let installShortcut: () -> Void
    let retry: () -> Void

    var body: some View {
        TranslationEditorSectionCard(role: .translation) {
            HStack(spacing: 8) {
                TranslationMascotBadgeView(mode: .vcc, accent: TranslationMascotRole.translation.accent)
                Text(TranslationMascotRole.translation.title)
                    .font(.headline)
                if state == .translating {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在翻译…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TranslationSpeechButton(
                    target: .translation,
                    role: .translation,
                    isSpeaking: isSpeaking,
                    isEnabled: canSpeak,
                    action: toggleSpeech
                )
            }
        } content: {
            ScrollView {
                Text(text.isEmpty ? "等待翻译…" : text)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: height)

            if case let .failed(message) = state {
                HStack(spacing: 8) {
                    Label(AppLocalizer.string(message), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer(minLength: 8)
                    if canInstallShortcut {
                        Button("添加快捷指令", action: installShortcut)
                    }
                    Button("重试", action: retry)
                }
                .controlSize(.small)
            }
        }
    }
}
