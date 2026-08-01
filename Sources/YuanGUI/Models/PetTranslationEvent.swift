import Foundation

enum TranslationInteractionSource: Equatable, Sendable {
    case selection
    case screenshot
}

enum PetTranslationEvent: Equatable, Sendable {
    case translationStarted(source: String, origin: TranslationInteractionSource)
    case translationFinished(source: String, result: String, origin: TranslationInteractionSource)
    case translationFailed(message: String, origin: TranslationInteractionSource)
    case speechStarted(target: TranslationSpeechTarget, origin: TranslationInteractionSource)
    case speechStopped(origin: TranslationInteractionSource)
    case interactionEnded(origin: TranslationInteractionSource)
}
