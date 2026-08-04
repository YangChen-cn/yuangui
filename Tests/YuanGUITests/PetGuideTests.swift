import XCTest
@testable import YuanGUI

@MainActor
final class PetGuideTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var capturedActions: [String] = []
    private var petIdle = true
    private var petLocked = false
    private var finderBundled = true
    private var finderEnabled = false

    override func setUp() {
        super.setUp()
        suiteName = "PetGuideTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        capturedActions = []
        petIdle = true
        petLocked = false
        finderBundled = true
        finderEnabled = false
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeCoordinator() -> PetGuideCoordinator {
        PetGuideCoordinator(
            defaults: defaults,
            canPresentTip: { [unowned self] in petIdle },
            isPetInteractionLocked: { [unowned self] in petLocked },
            finderExtensionBundled: { [unowned self] in finderBundled },
            finderExtensionEnabled: { [unowned self] in finderEnabled },
            actions: PetGuideCoordinator.Actions(
                beginRegionScreenshot: { [unowned self] in capturedActions.append("screenshot") },
                beginScreenshotTranslation: { [unowned self] in capturedActions.append("screenshotTranslation") },
                startFocus: { [unowned self] in capturedActions.append("focus") },
                openMusic: { [unowned self] in capturedActions.append("music") },
                openDiary: { [unowned self] in capturedActions.append("diary") },
                openQuickToolsSettings: { [unowned self] in capturedActions.append("quickTools") },
                openFinderExtensionManagement: { [unowned self] in capturedActions.append("finder") },
                unlockPet: { [unowned self] in petLocked = false },
                presentScreenshotFeedback: { [unowned self] in capturedActions.append("feedback") }
            )
        )
    }

    private func progressToToolsPhase(_ coordinator: PetGuideCoordinator) {
        coordinator.startOnboarding()
        coordinator.performPrimaryAction() // intro → contextMenu
        coordinator.performPrimaryAction() // contextMenu → tools
    }

    // MARK: - 首次启动 / 完成状态

    func testFirstLaunchIsEligibleForOnboarding() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.hasCompletedCurrentOnboarding)

        coordinator.startOnboarding()
        XCTAssertTrue(coordinator.isOnboardingActive)
        XCTAssertEqual(coordinator.onboardingPhase, .intro)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.intro")
    }

    func testCompletedVersionPreventsAutomaticOnboarding() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        XCTAssertTrue(makeCoordinator().hasCompletedCurrentOnboarding)
    }

    func testRestartOnboardingWorksAfterCompletion() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        let coordinator = makeCoordinator()
        coordinator.restartOnboarding()
        XCTAssertTrue(coordinator.isOnboardingActive)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.intro")
    }

    // MARK: - 步骤推进

    func testOnboardingProgressesThroughAllStepsToCompletion() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.tools")

        coordinator.performPrimaryAction() // 试试截图
        XCTAssertEqual(capturedActions, ["screenshot"])
        // 工具步骤不自动前进，等待截图会话结束
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.tools")

        coordinator.handleToolSessionEnded(true)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.finder")
        XCTAssertEqual(capturedActions, ["screenshot", "feedback"])
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .openFinderExtensionSettings)

        coordinator.performPrimaryAction() // 开启 Finder 增强
        XCTAssertEqual(capturedActions.last, "finder")
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.finder")

        // 用户从系统设置返回后扩展变为已启用
        finderEnabled = true
        coordinator.finderExtensionStatusDidChange(enabled: true)
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .next)

        coordinator.performPrimaryAction() // 开始使用
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertEqual(
            defaults.integer(forKey: PetGuideCoordinator.completedVersionKey),
            PetGuideCoordinator.onboardingVersion
        )
    }

    func testFinderAlreadyEnabledShowsEnabledMessage() {
        finderEnabled = true
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction() // 试试截图 → 启动工具会话
        coordinator.handleToolSessionEnded(false)

        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.finder")
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .next)

        coordinator.performPrimaryAction()
        XCTAssertFalse(coordinator.isOnboardingActive)
    }

    func testFinderNotBundledSkipsFinderStep() {
        finderBundled = false
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction() // 试试截图 → 启动工具会话
        coordinator.handleToolSessionEnded(false)

        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertEqual(
            defaults.integer(forKey: PetGuideCoordinator.completedVersionKey),
            PetGuideCoordinator.onboardingVersion
        )
    }

    func testScreenshotTranslationSecondaryStartsToolAndAdvancesOnCancel() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)

        coordinator.performSecondaryAction() // 试试截图翻译
        XCTAssertEqual(capturedActions, ["screenshotTranslation"])

        coordinator.handleToolSessionEnded(false)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)
        XCTAssertFalse(capturedActions.contains("feedback"))
    }

    func testLaterOnIntroDismissesWithoutCompleting() {
        let coordinator = makeCoordinator()
        coordinator.startOnboarding()
        coordinator.performSecondaryAction() // 以后再说

        XCTAssertNil(coordinator.currentGuide)
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(defaults.integer(forKey: PetGuideCoordinator.completedVersionKey), 0)
    }

    func testLaterOnFinderCompletesOnboarding() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction() // 试试截图 → 启动工具会话
        coordinator.handleToolSessionEnded(false)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)

        coordinator.performSecondaryAction() // 以后再说
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(
            defaults.integer(forKey: PetGuideCoordinator.completedVersionKey),
            PetGuideCoordinator.onboardingVersion
        )
    }

    func testCloseButtonOnToolsStepDismissesWithoutCompleting() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.dismissCurrentGuide()
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(defaults.integer(forKey: PetGuideCoordinator.completedVersionKey), 0)
    }

    // MARK: - 锁定状态

    func testLockedPetPresentsUnlockVariant() {
        petLocked = true
        let coordinator = makeCoordinator()
        coordinator.startOnboarding()
        coordinator.performPrimaryAction() // intro → contextMenu

        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.contextMenu")
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .unlockPet)

        coordinator.performPrimaryAction() // 临时解锁
        XCTAssertFalse(petLocked)
        // 解锁后重新展示该步骤，用户可以直接右键试试
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .next)
    }

    // MARK: - Feature tips

    func testFeatureTipsRequireOnboardingCompletion() {
        let coordinator = makeCoordinator()
        coordinator.considerFeatureTip()
        XCTAssertNil(coordinator.currentGuide)
    }

    func testFeatureTipsRequireIdlePet() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        petIdle = false
        let coordinator = makeCoordinator()
        coordinator.considerFeatureTip()
        XCTAssertNil(coordinator.currentGuide)

        petIdle = true
        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.selectionTranslation")
    }

    func testFeatureTipsPresentInOrderAndDismissMarksShown() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        let coordinator = makeCoordinator()

        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.selectionTranslation")
        XCTAssertEqual(coordinator.activeFeatureTip, .selectionTranslation)

        coordinator.performSecondaryAction() // 以后再说
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertTrue(coordinator.isTipShown(.selectionTranslation))

        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.screenshotTranslation")
        // 已显示过的 tip 不再自动出现
        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.screenshotTranslation")
    }

    func testFeatureTipPrimaryActionDispatchesAndMarksShown() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        // 标记前面的 tip 已显示，让 focus tip 成为下一个
        defaults.set(true, forKey: PetGuideCoordinator.featureTipPrefix + FeatureTipID.selectionTranslation.rawValue)
        defaults.set(true, forKey: PetGuideCoordinator.featureTipPrefix + FeatureTipID.screenshotTranslation.rawValue)
        let coordinator = makeCoordinator()

        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.focus")

        coordinator.performPrimaryAction() // 开始 25 分钟
        XCTAssertEqual(capturedActions, ["focus"])
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertTrue(coordinator.isTipShown(.focus))
    }

    func testFinderTipRequiresBundledAndDisabledExtension() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        for tip in FeatureTipID.allCases where tip != .finderExtension {
            defaults.set(true, forKey: PetGuideCoordinator.featureTipPrefix + tip.rawValue)
        }

        finderBundled = false
        XCTAssertNil(considerTip(in: makeCoordinator()))

        finderBundled = true
        finderEnabled = true
        XCTAssertNil(considerTip(in: makeCoordinator()))

        finderEnabled = false
        XCTAssertEqual(considerTip(in: makeCoordinator())?.id, "tip.finderExtension")
    }

    func testActiveOnboardingGuideIsNotReplacedByFeatureTip() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        let coordinator = makeCoordinator()
        coordinator.restartOnboarding()

        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.intro")
        XCTAssertNil(coordinator.activeFeatureTip)
    }

    func testScreenshotTipCompletionMarksShown() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        let coordinator = makeCoordinator()
        // 直接进入 screenshotTranslation tip（跳过 selectionTranslation）
        skipAllTipsExcept(.screenshotTranslation)
        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.activeFeatureTip, .screenshotTranslation)

        coordinator.performPrimaryAction() // 试试
        XCTAssertEqual(capturedActions, ["screenshotTranslation"])
        // 工具会话结束后 tip 收尾
        coordinator.handleToolSessionEnded(true)
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertTrue(coordinator.isTipShown(.screenshotTranslation))
    }

    private func skipAllTipsExcept(_ keep: FeatureTipID) {
        for tip in FeatureTipID.allCases where tip != keep {
            defaults.set(true, forKey: PetGuideCoordinator.featureTipPrefix + tip.rawValue)
        }
    }

    private func considerTip(in coordinator: PetGuideCoordinator) -> PetGuide? {
        coordinator.considerFeatureTip()
        return coordinator.currentGuide
    }
}
