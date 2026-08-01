import Foundation

enum PetTranslationActivity: Equatable {
    case translating
    case finished
    case failed
    case speaking(TranslationSpeechTarget)
}
