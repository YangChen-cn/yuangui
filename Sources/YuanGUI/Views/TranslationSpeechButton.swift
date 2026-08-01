import SwiftUI

struct TranslationSpeechButton: View {
    let target: TranslationSpeechTarget
    let isSpeaking: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isSpeaking ? Color.accentColor : Color.secondary)
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private var label: String {
        let key: String
        switch (target, isSpeaking) {
        case (.source, false): key = "朗读原文"
        case (.source, true): key = "停止朗读原文"
        case (.translation, false): key = "朗读译文"
        case (.translation, true): key = "停止朗读译文"
        }
        return AppLocalizer.string(key)
    }
}
