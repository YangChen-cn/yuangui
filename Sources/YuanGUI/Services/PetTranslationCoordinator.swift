import Foundation

@MainActor
final class PetTranslationCoordinator: PetTranslationEventHandling {
    private weak var pet: PetStore?
    private var activeOrigin: TranslationInteractionSource?

    init(pet: PetStore) {
        self.pet = pet
    }

    func handle(_ event: PetTranslationEvent) {
        switch event {
        case let .translationStarted(_, origin):
            guard let pet,
                  pet.presentTranslationActivity(
                .translating,
                message: AppLocalizer.string("translation.pet.translating")
            ) else {
                activeOrigin = nil
                return
            }
            activeOrigin = origin
        case let .translationFinished(_, _, origin):
            guard activeOrigin == origin else { return }
            guard pet?.presentTranslationActivity(
                .finished,
                message: AppLocalizer.string("translation.pet.finished"),
                duration: 7
            ) == true else {
                activeOrigin = nil
                return
            }
        case let .translationFailed(_, origin):
            guard activeOrigin == origin else { return }
            guard pet?.presentTranslationActivity(
                .failed,
                message: AppLocalizer.string("translation.pet.failed"),
                duration: 8
            ) == true else {
                activeOrigin = nil
                return
            }
        case let .speechStarted(target, origin):
            let messageKey = target == .source
                ? "translation.pet.speakingSource"
                : "translation.pet.speakingResult"
            guard let pet,
                  pet.presentTranslationActivity(
                .speaking(target),
                message: AppLocalizer.string(messageKey)
            ) else {
                activeOrigin = nil
                return
            }
            activeOrigin = origin
        case let .speechStopped(origin), let .interactionEnded(origin):
            guard activeOrigin == origin else { return }
            activeOrigin = nil
            pet?.endTranslationActivity()
        }
    }
}
