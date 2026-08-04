import Foundation

/// A single guide step shown in the pet bubble. Actions are represented as
/// enum values and dispatched by `PetGuideCoordinator` — no closures are
/// persisted in the model.
struct PetGuide: Identifiable, Equatable {
    let id: String
    let message: String
    let primaryTitle: String?
    let primaryAction: GuideAction?
    let secondaryTitle: String?
    let secondaryAction: GuideAction?

    init(
        id: String,
        message: String,
        primaryTitle: String? = nil,
        primaryAction: GuideAction? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: GuideAction? = nil
    ) {
        self.id = id
        self.message = message
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }
}

enum GuideAction: Equatable, Sendable {
    /// Advance to the next onboarding step.
    case next
    /// Dismiss the current guide ("以后再说").
    case dismiss
    case regionScreenshot
    case screenshotTranslation
    case translateSelection
    case openFinderExtensionSettings
    case openQuickToolsSettings
    case startFocus
    case openMusic
    case openDiary
    /// Temporarily unlock the pet so the user can try its interactions.
    case unlockPet
}

/// Lightweight one-time feature discovery prompts presented after onboarding.
enum FeatureTipID: String, CaseIterable, Sendable {
    case selectionTranslation
    case screenshotTranslation
    case focus
    case diary
    case music
    case finderExtension
}
