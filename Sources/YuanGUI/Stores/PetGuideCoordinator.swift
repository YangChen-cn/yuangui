import Combine
import Foundation

/// Owns onboarding and lightweight feature discovery. The pet stays the only
/// surface: every step is presented as a bubble with at most two buttons that
/// dispatch to existing features through injected closures.
///
/// Precedence with the rest of the pet's messages is resolved once by
/// `PetAuxiliaryBubbleResolver` (shared by the view and the panel): running
/// tasks and urgent reminders outrank the guide; the guide outranks lyrics,
/// ambient chatter, weather and non-urgent smart states.
@MainActor
final class PetGuideCoordinator: ObservableObject {
    static let onboardingVersion = 1
    static let completedVersionKey = "onboarding.completedVersion"
    static let migrationKey = "onboarding.migration.v1"
    static let featureTipPrefix = "featureTip.shown."
    static let featureUsedPrefix = "featureUsed."
    static let featureTipsEnabledKey = "featureTips.enabled"

    /// Wait before the first feature-tip opportunity so new users settle in.
    static let initialTipDelay: TimeInterval = 90
    /// Long retry interval so tips never feel naggy.
    static let tipRetryInterval: TimeInterval = 30 * 60

    enum OnboardingPhase: Equatable {
        case idle
        case intro
        case contextMenu
        case tools
        case finder
        case complete
    }

    struct Actions {
        /// Starts a region screenshot; true = a session started (it will later
        /// report exactly one end via `handleToolSessionEnded`), false = it
        /// could not start and nothing will follow.
        var beginRegionScreenshot: () -> Bool = { false }
        var beginScreenshotTranslation: () -> Bool = { false }
        /// Starts a focus session. The minutes parameter is always explicit so
        /// the promised duration matches the actual behavior (the tip says
        /// "开始 25 分钟" and starts exactly 25 minutes).
        var startFocus: (Int) -> Void = { _ in }
        var openMusic: () -> Void = {}
        var openDiary: () -> Void = {}
        var openQuickToolsSettings: () -> Void = {}
        var openFinderExtensionManagement: () -> Void = {}
        /// Runtime-only override; never persists the user's lock preference.
        var beginTemporaryInteractionUnlock: () -> Void = {}
        var endTemporaryInteractionUnlock: () -> Void = {}
        /// Short pet feedback after a guide-triggered screenshot succeeds.
        var presentScreenshotFeedback: () -> Void = {}
    }

    @Published private(set) var currentGuide: PetGuide?
    @Published private(set) var onboardingPhase: OnboardingPhase = .idle
    @Published private(set) var isOnboardingActive = false
    @Published private(set) var activeFeatureTip: FeatureTipID?

    private let defaults: UserDefaults
    private let canPresentTip: () -> Bool
    private let isPetInteractionLocked: () -> Bool
    private let finderExtensionBundled: () -> Bool
    private let finderExtensionEnabled: () -> Bool
    private let actions: Actions
    private var tipTask: Task<Void, Never>?
    private var pendingScreenshotTracking = false
    private var waitingForFinderEnablement = false

    init(
        defaults: UserDefaults = .standard,
        canPresentTip: @escaping () -> Bool,
        isPetInteractionLocked: @escaping () -> Bool,
        finderExtensionBundled: @escaping () -> Bool,
        finderExtensionEnabled: @escaping () -> Bool,
        actions: Actions = Actions()
    ) {
        self.defaults = defaults
        self.canPresentTip = canPresentTip
        self.isPetInteractionLocked = isPetInteractionLocked
        self.finderExtensionBundled = finderExtensionBundled
        self.finderExtensionEnabled = finderExtensionEnabled
        self.actions = actions
        runLegacyMigrationIfNeeded()
    }

    // MARK: - Lifecycle

    func start() {
        scheduleNextTipOpportunity(delay: Self.initialTipDelay)
    }

    func stop() {
        tipTask?.cancel()
        tipTask = nil
        // Never leave a runtime unlock behind, even on quit mid-walkthrough.
        actions.endTemporaryInteractionUnlock()
    }

    // MARK: - Onboarding

    var hasCompletedCurrentOnboarding: Bool {
        defaults.integer(forKey: Self.completedVersionKey) >= Self.onboardingVersion
    }

    /// Auto-start for a fresh install. Callers decide when it is appropriate;
    /// this coordinator stays silent for users who already completed it.
    func startOnboarding() {
        beginOnboarding(at: .intro)
    }

    /// The pet's context-menu entry and the settings page both call this.
    /// It works even after onboarding completed and never clears user settings.
    func restartOnboarding() {
        beginOnboarding(at: .intro)
    }

    private func beginOnboarding(at phase: OnboardingPhase) {
        // A restart replaces any in-flight walkthrough: restore the user's
        // original lock state first so nothing leaks across runs.
        actions.endTemporaryInteractionUnlock()
        isOnboardingActive = true
        activeFeatureTip = nil
        presentGuide(for: phase)
    }

    private func presentGuide(for phase: OnboardingPhase) {
        let previous = onboardingPhase
        if previous == .contextMenu, phase != .contextMenu {
            actions.endTemporaryInteractionUnlock()
        }
        onboardingPhase = phase
        if let guide = guideFor(phase) {
            currentGuide = guide
        } else {
            advanceOnboarding()
        }
    }

    private func advanceOnboarding() {
        switch onboardingPhase {
        case .intro: presentGuide(for: .contextMenu)
        case .contextMenu: presentGuide(for: .tools)
        case .tools: presentGuide(for: .finder)
        case .finder: presentGuide(for: .complete)
        case .complete, .idle: completeOnboarding()
        }
    }

    private func completeOnboarding() {
        isOnboardingActive = false
        onboardingPhase = .idle
        activeFeatureTip = nil
        currentGuide = nil
        waitingForFinderEnablement = false
        pendingScreenshotTracking = false
        actions.endTemporaryInteractionUnlock()
        defaults.set(Self.onboardingVersion, forKey: Self.completedVersionKey)
    }

    /// "以后再说" on non-final steps: stop without recording completion so a
    /// later launch can offer the walkthrough again.
    private func endOnboardingWithoutCompleting() {
        isOnboardingActive = false
        onboardingPhase = .idle
        activeFeatureTip = nil
        currentGuide = nil
        waitingForFinderEnablement = false
        pendingScreenshotTracking = false
        actions.endTemporaryInteractionUnlock()
    }

    // MARK: - Guide actions

    func performPrimaryAction() {
        guard let action = currentGuide?.primaryAction else { return }
        handle(action)
    }

    func performSecondaryAction() {
        guard let action = currentGuide?.secondaryAction else { return }
        handle(action)
    }

    /// Close button on the bubble: skips the current step. On the final step
    /// it records completion.
    func dismissCurrentGuide() {
        if isOnboardingActive {
            switch onboardingPhase {
            case .finder: presentGuide(for: .complete)
            case .complete: completeOnboarding()
            default: endOnboardingWithoutCompleting()
            }
        } else if let tip = activeFeatureTip {
            markTipShown(tip)
            activeFeatureTip = nil
            currentGuide = nil
        }
    }

    private func handle(_ action: GuideAction) {
        switch action {
        case .next:
            advanceOnboarding()
        case .dismiss:
            if isOnboardingActive {
                switch onboardingPhase {
                case .finder:
                    // "暂时不要" on Finder still lands on the closing message.
                    presentGuide(for: .complete)
                case .complete:
                    completeOnboarding()
                default:
                    endOnboardingWithoutCompleting()
                }
            } else if let tip = activeFeatureTip {
                markTipShown(tip)
                activeFeatureTip = nil
                currentGuide = nil
            }
        case .regionScreenshot:
            if actions.beginRegionScreenshot() {
                pendingScreenshotTracking = true
            }
        case .screenshotTranslation:
            if actions.beginScreenshotTranslation() {
                pendingScreenshotTracking = true
            }
        case .translateSelection:
            // Not used by the current guide set; the selection-translation tip
            // points at the shortcuts page instead.
            dismissCurrentGuide()
        case .openFinderExtensionSettings:
            actions.openFinderExtensionManagement()
            if isOnboardingActive, onboardingPhase == .finder {
                waitingForFinderEnablement = true
            } else if let tip = activeFeatureTip {
                markTipShown(tip)
                activeFeatureTip = nil
                currentGuide = nil
            }
        case .openQuickToolsSettings:
            actions.openQuickToolsSettings()
            finishActiveTip()
        case .startFocus:
            actions.startFocus(25)
            finishActiveTip()
        case .openMusic:
            actions.openMusic()
            finishActiveTip()
        case .openDiary:
            actions.openDiary()
            finishActiveTip()
        case .unlockPet:
            actions.beginTemporaryInteractionUnlock()
            presentGuide(for: onboardingPhase)
        }
    }

    /// Called by the app when a started capture session ends.
    /// `completed` is true only when an image was actually captured. A session
    /// that never started reports nothing, matching the `Bool` contract of
    /// `beginRegionScreenshot`/`beginScreenshotTranslation`.
    func handleToolSessionEnded(_ completed: Bool) {
        guard pendingScreenshotTracking else { return }
        pendingScreenshotTracking = false
        if isOnboardingActive, onboardingPhase == .tools {
            if completed {
                actions.presentScreenshotFeedback()
            }
            advanceOnboarding()
        } else if let tip = activeFeatureTip {
            markTipShown(tip)
            activeFeatureTip = nil
            currentGuide = nil
        }
    }

    /// The Finder extension becomes enabled while the finder step is waiting.
    func finderExtensionStatusDidChange(enabled: Bool) {
        guard waitingForFinderEnablement, enabled else { return }
        waitingForFinderEnablement = false
        guard isOnboardingActive, onboardingPhase == .finder else { return }
        presentGuide(for: .finder)
    }

    private func finishActiveTip() {
        guard let tip = activeFeatureTip else { return }
        markTipShown(tip)
        activeFeatureTip = nil
        currentGuide = nil
    }

    // MARK: - Feature usage tracking (local only, no analytics)

    func recordFeatureUsed(_ tip: FeatureTipID) {
        defaults.set(true, forKey: Self.featureUsedPrefix + tip.rawValue)
    }

    func hasUsedFeature(_ tip: FeatureTipID) -> Bool {
        defaults.bool(forKey: Self.featureUsedPrefix + tip.rawValue)
    }

    // MARK: - Feature tips

    var featureTipsEnabled: Bool {
        defaults.object(forKey: Self.featureTipsEnabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.featureTipsEnabledKey)
    }

    func setFeatureTipsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.featureTipsEnabledKey)
        if !enabled {
            // Drop any tip that is currently on screen.
            finishActiveTip()
        }
    }

    func considerFeatureTip() {
        guard featureTipsEnabled,
              currentGuide == nil,
              !isOnboardingActive,
              hasCompletedCurrentOnboarding,
              canPresentTip() else { return }
        for tip in FeatureTipID.allCases {
            guard !isTipShown(tip), !hasUsedFeature(tip) else { continue }
            if let guide = tipGuide(for: tip) {
                activeFeatureTip = tip
                currentGuide = guide
                return
            }
        }
    }

    func isTipShown(_ tip: FeatureTipID) -> Bool {
        defaults.bool(forKey: Self.featureTipPrefix + tip.rawValue)
    }

    private func markTipShown(_ tip: FeatureTipID) {
        defaults.set(true, forKey: Self.featureTipPrefix + tip.rawValue)
    }

    private func scheduleNextTipOpportunity(delay: TimeInterval) {
        tipTask?.cancel()
        tipTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.considerFeatureTip()
            self.scheduleNextTipOpportunity(delay: Self.tipRetryInterval)
        }
    }

    // MARK: - Legacy install migration

    /// Users who already had YuanGUI before onboarding existed must not be
    /// treated as fresh installs. Runs once per install; never resets any
    /// user configuration.
    private func runLegacyMigrationIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        defaults.set(true, forKey: Self.migrationKey)
        guard !hasCompletedCurrentOnboarding else { return }
        if Self.hasLegacyInstallEvidence(defaults: defaults) {
            defaults.set(Self.onboardingVersion, forKey: Self.completedVersionKey)
        }
    }

    static func hasLegacyInstallEvidence(defaults: UserDefaults) -> Bool {
        let evidenceKeys = [
            "hasSavedPetWindowPosition",
            "petWindowX",
            "petMode",
            "petScale",
            "focusDurationMinutes",
            "dashboardStyle",
            "interactionLocked",
            "smartReactionsEnabled",
            "ambientChatterIntervalMinutes",
            "weatherAnnouncementsEnabled",
            "bedtimeReminderEnabled",
            // Quick tools hot-key configuration.
            "quickTools.screenshotHotKey",
            "quickTools.translationHotKey",
            "quickTools.screenshotTranslationHotKey"
        ]
        return evidenceKeys.contains { defaults.object(forKey: $0) != nil }
    }

    // MARK: - Guide content

    private func guideFor(_ phase: OnboardingPhase) -> PetGuide? {
        switch phase {
        case .idle:
            return nil
        case .intro:
            return PetGuide(
                id: "onboarding.intro",
                message: AppLocalizer.string("guide.intro.message"),
                primaryTitle: AppLocalizer.string("guide.intro.primary"),
                primaryAction: .next,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .contextMenu:
            if isPetInteractionLocked() {
                return PetGuide(
                    id: "onboarding.contextMenu",
                    message: AppLocalizer.string("guide.contextMenu.lockedMessage"),
                    primaryTitle: AppLocalizer.string("guide.contextMenu.unlock"),
                    primaryAction: .unlockPet,
                    secondaryTitle: AppLocalizer.string("guide.later"),
                    secondaryAction: .dismiss
                )
            }
            return PetGuide(
                id: "onboarding.contextMenu",
                message: AppLocalizer.string("guide.contextMenu.message"),
                primaryTitle: AppLocalizer.string("guide.contextMenu.primary"),
                primaryAction: .next,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .tools:
            return PetGuide(
                id: "onboarding.tools",
                message: AppLocalizer.string("guide.tools.message"),
                primaryTitle: AppLocalizer.string("guide.tools.tryScreenshot"),
                primaryAction: .regionScreenshot,
                secondaryTitle: AppLocalizer.string("guide.tools.tryScreenshotTranslation"),
                secondaryAction: .screenshotTranslation
            )
        case .finder:
            guard finderExtensionBundled() else { return nil }
            if finderExtensionEnabled() {
                return PetGuide(
                    id: "onboarding.finder",
                    message: AppLocalizer.string("guide.finder.enabledMessage"),
                    primaryTitle: AppLocalizer.string("guide.complete.primary"),
                    primaryAction: .next
                )
            }
            return PetGuide(
                id: "onboarding.finder",
                message: AppLocalizer.string("guide.finder.disabledMessage"),
                primaryTitle: AppLocalizer.string("guide.finder.enable"),
                primaryAction: .openFinderExtensionSettings,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .complete:
            return PetGuide(
                id: "onboarding.complete",
                message: AppLocalizer.string("guide.complete.message"),
                primaryTitle: AppLocalizer.string("guide.complete.primary"),
                primaryAction: .next
            )
        }
    }

    private func tipGuide(for tip: FeatureTipID) -> PetGuide? {
        switch tip {
        case .selectionTranslation:
            return PetGuide(
                id: "tip.selectionTranslation",
                message: AppLocalizer.string("tip.selectionTranslation.message"),
                primaryTitle: AppLocalizer.string("tip.selectionTranslation.primary"),
                primaryAction: .openQuickToolsSettings,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .screenshotTranslation:
            return PetGuide(
                id: "tip.screenshotTranslation",
                message: AppLocalizer.string("tip.screenshotTranslation.message"),
                primaryTitle: AppLocalizer.string("tip.screenshotTranslation.primary"),
                primaryAction: .screenshotTranslation,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .focus:
            return PetGuide(
                id: "tip.focus",
                message: AppLocalizer.string("tip.focus.message"),
                primaryTitle: AppLocalizer.string("tip.focus.primary"),
                primaryAction: .startFocus,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .diary:
            return PetGuide(
                id: "tip.diary",
                message: AppLocalizer.string("tip.diary.message"),
                primaryTitle: AppLocalizer.string("tip.diary.primary"),
                primaryAction: .openDiary,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .music:
            return PetGuide(
                id: "tip.music",
                message: AppLocalizer.string("tip.music.message"),
                primaryTitle: AppLocalizer.string("tip.music.primary"),
                primaryAction: .openMusic,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        case .finderExtension:
            guard finderExtensionBundled(), !finderExtensionEnabled() else { return nil }
            return PetGuide(
                id: "tip.finderExtension",
                message: AppLocalizer.string("tip.finder.message"),
                primaryTitle: AppLocalizer.string("tip.finder.primary"),
                primaryAction: .openFinderExtensionSettings,
                secondaryTitle: AppLocalizer.string("guide.later"),
                secondaryAction: .dismiss
            )
        }
    }
}
