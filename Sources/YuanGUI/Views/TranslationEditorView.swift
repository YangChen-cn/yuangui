import SwiftUI
import Translation

struct TranslationEditorView: View {
    @ObservedObject var store: TranslationEditorStore
    @ObservedObject var layout: TranslationWindowLayoutModel
    let close: () -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TranslationEditorHeaderView(
                sourceApplicationName: store.sourceApplicationName,
                engineTitle: store.engineTitle,
                targetLanguage: targetLanguageBinding
            )
            TranslationSourceSection(
                text: sourceTextBinding,
                detectedLanguage: store.detectedSourceLanguage,
                height: layout.value.sourceHeight,
                isSpeaking: store.speakingTarget == .source,
                canSpeak: store.canSpeakSource,
                formatLineBreaks: store.formatSourceLineBreaks,
                toggleSpeech: store.toggleSourceSpeech
            )
            TranslationResultSection(
                text: store.translatedText,
                state: store.state,
                height: layout.value.resultHeight,
                isSpeaking: store.speakingTarget == .translation,
                canSpeak: store.canSpeakTranslation,
                canInstallShortcut: store.canInstallShortcut,
                toggleSpeech: store.toggleTranslationSpeech,
                installShortcut: store.installShortcut,
                retry: retryTranslation
            )
            TranslationEditorFooterView(
                message: store.message,
                replacementHint: store.targetSnapshot.canReplace ? nil : store.replacementHint,
                canCopy: !store.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                canReplace: store.canReplace,
                targetCanReplace: store.targetSnapshot.canReplace,
                close: close,
                copy: store.copyTranslation,
                replace: replaceOriginal
            )
        }
        .padding(14)
        .frame(
            minWidth: 400,
            maxWidth: .infinity,
            minHeight: 280,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(.regularMaterial)
        .transaction { transaction in transaction.animation = nil }
        .task(id: translationRequestID) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await requestTranslation()
        }
        .translationTask(configuration) { session in
            await store.performTranslation(using: session)
        }
        .onDisappear(perform: store.stopSpeaking)
    }

    private var sourceTextBinding: Binding<String> {
        Binding(
            get: { store.editableSourceText },
            set: store.updateEditableSourceText
        )
    }

    private var targetLanguageBinding: Binding<QuickToolLanguage> {
        Binding(
            get: { store.targetLanguage },
            set: store.requestTargetLanguage
        )
    }

    private func refreshConfiguration() {
        var newConfiguration = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: store.targetLanguage.rawValue)
        )
        newConfiguration.invalidate()
        configuration = newConfiguration
    }

    private func requestTranslation() async {
        if store.usesShortcutTranslation {
            configuration = nil
            await store.performShortcutTranslation()
        } else if store.usesOnlineTranslation {
            configuration = nil
            await store.performOnlineTranslation()
        } else {
            refreshConfiguration()
        }
    }

    private func retryTranslation() {
        Task { await requestTranslation() }
    }

    private func replaceOriginal() {
        Task { await store.replaceOriginal() }
    }

    private var translationRequestID: String {
        store.targetLanguage.rawValue + "\u{0}" + store.editableSourceText
    }
}
