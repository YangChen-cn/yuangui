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
            activeOrigin = origin
            pet?.presentTranslationActivity(
                .translating,
                message: AppLocalizer.string("translation.pet.translating")
            )
        case let .translationFinished(_, _, origin):
            guard activeOrigin == origin else { return }
            pet?.presentTranslationActivity(
                .finished,
                message: AppLocalizer.string("translation.pet.finished"),
                duration: 7
            )
        case let .translationFailed(_, origin):
            guard activeOrigin == origin else { return }
            pet?.presentTranslationActivity(
                .failed,
                message: AppLocalizer.string("translation.pet.failed"),
                duration: 8
            )
        case let .speechStarted(target, origin):
            activeOrigin = origin
            let messageKey = target == .source
                ? "translation.pet.speakingSource"
                : "translation.pet.speakingResult"
            pet?.presentTranslationActivity(
                .speaking(target),
                message: AppLocalizer.string(messageKey)
            )
        case let .speechStopped(origin), let .interactionEnded(origin):
            guard activeOrigin == origin else { return }
            activeOrigin = nil
            pet?.endTranslationActivity()
        }
    }
}
