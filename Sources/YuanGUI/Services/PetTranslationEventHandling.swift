import Foundation

@MainActor
protocol PetTranslationEventHandling: AnyObject {
    func handle(_ event: PetTranslationEvent)
}
