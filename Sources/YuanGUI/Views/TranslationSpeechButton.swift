import SwiftUI

struct TranslationSpeechButton: View {
    let target: TranslationSpeechTarget
    let role: TranslationMascotRole
    let isSpeaking: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2")
                .labelStyle(.iconOnly)
                .frame(width: 27, height: 25)
                .background(role.accent.opacity(isSpeaking ? 0.2 : 0.09), in: Circle())
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isSpeaking ? role.accent : Color.secondary)
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
