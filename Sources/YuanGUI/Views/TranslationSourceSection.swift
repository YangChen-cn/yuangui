import SwiftUI

struct TranslationSourceSection: View {
    @Binding var text: String
    let detectedLanguage: String?
    let height: CGFloat
    let isSpeaking: Bool
    let canSpeak: Bool
    let formatLineBreaks: () -> Void
    let toggleSpeech: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TranslationEditorSectionCard {
            HStack(spacing: 8) {
                Text("原文")
                    .font(.headline)
                if let detectedLanguage {
                    Text(languageTitle(detectedLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("整理换行", systemImage: "text.alignleft", action: formatLineBreaks)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("将被网页压成一行的列表符号恢复为分行显示")
                TranslationSpeechButton(
                    target: .source,
                    isSpeaking: isSpeaking,
                    isEnabled: canSpeak,
                    action: toggleSpeech
                )
            }
        } content: {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                if text.isEmpty {
                    Text("输入要翻译的文字…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: height)
            .background(.background.opacity(0.72), in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(.separator.opacity(0.42), lineWidth: 0.7)
            }
        }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }

    private func languageTitle(_ identifier: String) -> String {
        Locale.current.localizedString(forLanguageCode: identifier) ?? identifier
    }
}
