import XCTest
@testable import YuanGUI

@MainActor
final class PetGuideTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var capturedActions: [String] = []
    private var capturedFocusMinutes: [Int] = []
    private var petIdle = true
    /// Effective lock state reported to the coordinator (persisted lock minus
    /// any temporary unlock), mirroring `PetStore.effectiveInteractionLocked`.
    private var petLocked = false
    /// The user's persisted lock preference; temporary unlocks must not touch it.
    private var persistedPetLocked = false
    private var finderBundled = true
    private var finderEnabled = false
    private var screenshotStarts = true
    private var screenshotTranslationStarts = true

    override func setUp() {
        super.setUp()
        suiteName = "PetGuideTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        capturedActions = []
        capturedFocusMinutes = []
        petIdle = true
        petLocked = false
        persistedPetLocked = false
        finderBundled = true
        finderEnabled = false
        screenshotStarts = true
        screenshotTranslationStarts = true
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
                beginRegionScreenshot: { [unowned self] in
                    capturedActions.append("screenshot")
                    return screenshotStarts
                },
                beginScreenshotTranslation: { [unowned self] in
                    capturedActions.append("screenshotTranslation")
                    return screenshotTranslationStarts
                },
                startFocus: { [unowned self] minutes in
                    capturedActions.append("focus")
                    capturedFocusMinutes.append(minutes)
                },
                openMusic: { [unowned self] in capturedActions.append("music") },
                openDiary: { [unowned self] in capturedActions.append("diary") },
                openQuickToolsSettings: { [unowned self] in capturedActions.append("quickTools") },
                openFinderExtensionManagement: { [unowned self] in capturedActions.append("finder") },
                beginTemporaryInteractionUnlock: { [unowned self] in
                    capturedActions.append("tempUnlockBegin")
                    petLocked = false
                },
                endTemporaryInteractionUnlock: { [unowned self] in
                    capturedActions.append("tempUnlockEnd")
                    if persistedPetLocked { petLocked = true }
                },
                presentScreenshotFeedback: { [unowned self] in capturedActions.append("feedback") }
            )
        )
    }

    private func progressToToolsPhase(_ coordinator: PetGuideCoordinator) {
        coordinator.startOnboarding()
        coordinator.performPrimaryAction() // intro → contextMenu
        coordinator.performPrimaryAction() // contextMenu → tools
    }

    /// Runs the tools step with a started capture session and ends it, landing
    /// on the finder step.
    private func progressToFinderPhase(_ coordinator: PetGuideCoordinator) {
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction() // 试试截图 → starts session
        coordinator.handleToolSessionEnded(true)
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

    /// `beginOnboarding` defensively restores any in-flight temporary unlock,
    /// so action lists also contain restore calls outside the assertions that
    /// care about a specific tool action.
    private func actionsOf(_ name: String) -> [String] {
        capturedActions.filter { $0 == name }
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

    // MARK: - 步骤推进（含 complete step）

    func testOnboardingProgressesThroughAllStepsToCompletion() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.tools")

        coordinator.performPrimaryAction() // 试试截图
        XCTAssertEqual(actionsOf("screenshot"), ["screenshot"])
        // 工具步骤不自动前进，等待截图会话结束
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.tools")

        coordinator.handleToolSessionEnded(true)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.finder")
        XCTAssertEqual(actionsOf("feedback"), ["feedback"])
        XCTAssertLessThan(
            capturedActions.firstIndex(of: "screenshot") ?? -1,
            capturedActions.firstIndex(of: "feedback") ?? -1
        )
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .openFinderExtensionSettings)

        coordinator.performPrimaryAction() // 开启 Finder 增强
        XCTAssertEqual(capturedActions.last, "finder")
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.finder")

        // 用户从系统设置返回后扩展变为已启用
        finderEnabled = true
        coordinator.finderExtensionStatusDidChange(enabled: true)
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .next)

        coordinator.performPrimaryAction() // 开始使用 → complete step
        XCTAssertEqual(coordinator.onboardingPhase, .complete)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.complete")

        coordinator.performPrimaryAction() // 开始使用 → 记录完成
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertEqual(
            defaults.integer(forKey: PetGuideCoordinator.completedVersionKey),
            PetGuideCoordinator.onboardingVersion
        )
    }

    func testFinderAlreadyEnabledShowsEnabledMessageThenComplete() {
        finderEnabled = true
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction() // 试试截图 → 启动工具会话
        coordinator.handleToolSessionEnded(false)

        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.finder")
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .next)

        coordinator.performPrimaryAction() // → complete step
        XCTAssertEqual(coordinator.onboardingPhase, .complete)
        coordinator.performPrimaryAction() // → 完成
        XCTAssertFalse(coordinator.isOnboardingActive)
    }

    func testFinderNotBundledSkipsToCompleteStep() {
        finderBundled = false
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction() // 试试截图 → 启动工具会话
        coordinator.handleToolSessionEnded(false)

        // Finder 步骤被跳过，但结束对白仍然出现
        XCTAssertEqual(coordinator.onboardingPhase, .complete)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.complete")

        coordinator.performPrimaryAction()
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(
            defaults.integer(forKey: PetGuideCoordinator.completedVersionKey),
            PetGuideCoordinator.onboardingVersion
        )
    }

    func testScreenshotTranslationSecondaryStartsToolAndAdvancesOnCancel() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)

        coordinator.performSecondaryAction() // 试试截图翻译
        XCTAssertEqual(actionsOf("screenshotTranslation"), ["screenshotTranslation"])

        coordinator.handleToolSessionEnded(false)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)
        XCTAssertFalse(capturedActions.contains("feedback"))
    }

    func testToolCancelStillAdvancesOnboarding() {
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)
        coordinator.performPrimaryAction()
        coordinator.handleToolSessionEnded(false)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)
    }

    func testScreenshotSynchronousRejectionDoesNotStallOnboarding() {
        // 截图同步失败（权限拒绝、已在录制等）：session 未启动，
        // 之后也不会产生 ended 回调，引导必须继续留在 tools 步骤而不是卡死。
        screenshotStarts = false
        let coordinator = makeCoordinator()
        progressToToolsPhase(coordinator)

        coordinator.performPrimaryAction() // 试试截图
        XCTAssertEqual(actionsOf("screenshot"), ["screenshot"])
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.tools")

        // 即使迟到回调到达（契约下不该发生），也不能错误推进
        coordinator.handleToolSessionEnded(true)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.tools")
        XCTAssertEqual(coordinator.onboardingPhase, .tools)

        // 用户可以再次尝试，且失败后可以正常退出
        coordinator.dismissCurrentGuide()
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(defaults.integer(forKey: PetGuideCoordinator.completedVersionKey), 0)
    }

    // MARK: - “以后再说”语义

    func testLaterOnIntroDismissesWithoutCompleting() {
        let coordinator = makeCoordinator()
        coordinator.startOnboarding()
        coordinator.performSecondaryAction() // 以后再说

        XCTAssertNil(coordinator.currentGuide)
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(defaults.integer(forKey: PetGuideCoordinator.completedVersionKey), 0)
    }

    func testLaterOnFinderLandsOnCompleteStep() {
        let coordinator = makeCoordinator()
        progressToFinderPhase(coordinator)
        XCTAssertEqual(coordinator.onboardingPhase, .finder)

        coordinator.performSecondaryAction() // 暂时不要 → complete step
        XCTAssertEqual(coordinator.onboardingPhase, .complete)
        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.complete")

        coordinator.performPrimaryAction() // 开始使用 → 记录完成
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

    func testCloseButtonOnCompleteStepRecordsCompletion() {
        let coordinator = makeCoordinator()
        progressToFinderPhase(coordinator)
        coordinator.dismissCurrentGuide() // finder X → complete step
        XCTAssertEqual(coordinator.onboardingPhase, .complete)

        coordinator.dismissCurrentGuide() // complete X → 记录完成
        XCTAssertFalse(coordinator.isOnboardingActive)
        XCTAssertEqual(
            defaults.integer(forKey: PetGuideCoordinator.completedVersionKey),
            PetGuideCoordinator.onboardingVersion
        )
    }

    // MARK: - 锁定状态与临时解锁

    func testLockedPetPresentsUnlockVariantAndRestoresLock() {
        persistedPetLocked = true
        petLocked = true
        let coordinator = makeCoordinator()
        coordinator.startOnboarding()
        coordinator.performPrimaryAction() // intro → contextMenu

        XCTAssertEqual(coordinator.currentGuide?.id, "onboarding.contextMenu")
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .unlockPet)

        coordinator.performPrimaryAction() // 临时解锁
        XCTAssertEqual(actionsOf("tempUnlockBegin"), ["tempUnlockBegin"])
        XCTAssertFalse(petLocked)
        // 解锁后重新展示该步骤，用户可以直接右键试试
        XCTAssertEqual(coordinator.currentGuide?.primaryAction, .next)

        coordinator.performPrimaryAction() // 我知道了 → tools
        // 离开 context-menu step 必须恢复用户原来的锁定状态
        XCTAssertTrue(capturedActions.contains("tempUnlockEnd"))
        XCTAssertTrue(capturedActions.last == "tempUnlockEnd")
    }

    func testTemporaryUnlockNeverPersists() {
        let suite = "PetGuideTempUnlock-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setInteractionLocked(true)
        XCTAssertTrue(store.interactionLocked)
        XCTAssertTrue(store.effectiveInteractionLocked)

        store.beginTemporaryInteractionUnlock()
        XCTAssertFalse(store.effectiveInteractionLocked)
        // 持久偏好未被修改
        XCTAssertTrue(store.interactionLocked)
        XCTAssertTrue(defaults.bool(forKey: "interactionLocked"))

        store.endTemporaryInteractionUnlock()
        XCTAssertTrue(store.effectiveInteractionLocked)
        XCTAssertTrue(defaults.bool(forKey: "interactionLocked"))
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
        skipAllTipsExcept(.focus)
        let coordinator = makeCoordinator()

        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.focus")

        coordinator.performPrimaryAction() // 开始 25 分钟
        XCTAssertEqual(capturedActions, ["focus"])
        XCTAssertEqual(capturedFocusMinutes, [25])
        XCTAssertNil(coordinator.currentGuide)
        XCTAssertTrue(coordinator.isTipShown(.focus))
    }

    func testUsedFeatureSkipsItsTip() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        // 前面所有 tip 都显示过，只剩 music
        for tip in FeatureTipID.allCases where tip != .music {
            defaults.set(true, forKey: PetGuideCoordinator.featureTipPrefix + tip.rawValue)
        }
        let coordinator = makeCoordinator()

        coordinator.considerFeatureTip()
        XCTAssertEqual(coordinator.currentGuide?.id, "tip.music")

        // 用户已经用过音乐后，音乐 tip 不再出现
        coordinator.recordFeatureUsed(.music)
        coordinator.performSecondaryAction()
        XCTAssertNil(considerTip(in: coordinator))
    }

    func testFinderTipRequiresBundledAndDisabledExtension() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        skipAllTipsExcept(.finderExtension)

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

    func testFeatureTipsCanBeDisabled() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        let coordinator = makeCoordinator()

        coordinator.setFeatureTipsEnabled(false)
        XCTAssertNil(considerTip(in: coordinator))

        coordinator.setFeatureTipsEnabled(true)
        XCTAssertEqual(considerTip(in: coordinator)?.id, "tip.selectionTranslation")
    }

    func testDisablingTipsDropsCurrentlyShownTip() {
        defaults.set(PetGuideCoordinator.onboardingVersion, forKey: PetGuideCoordinator.completedVersionKey)
        let coordinator = makeCoordinator()
        coordinator.considerFeatureTip()
        XCTAssertNotNil(coordinator.currentGuide)

        coordinator.setFeatureTipsEnabled(false)
        XCTAssertNil(coordinator.currentGuide)
    }

    // MARK: - Legacy migration

    func testLegacyMigrationKeepsFreshInstallEligible() {
        _ = makeCoordinator()
        XCTAssertEqual(defaults.integer(forKey: PetGuideCoordinator.completedVersionKey), 0)
        XCTAssertFalse(makeCoordinator().hasCompletedCurrentOnboarding)
    }

    func testLegacyMigrationMarksOldInstallCompleted() {
        // 老版本用户写过桌宠位置等配置
        defaults.set(42.0, forKey: "petWindowX")
        defaults.set(42.0, forKey: "petWindowY")
        defaults.set(true, forKey: "hasSavedPetWindowPosition")

        _ = makeCoordinator()
        XCTAssertTrue(makeCoordinator().hasCompletedCurrentOnboarding)
        // 用户配置未被重置
        XCTAssertEqual(defaults.double(forKey: "petWindowX"), 42.0)
    }

    func testLegacyMigrationRunsOnlyOnce() {
        defaults.set(1.0, forKey: "petScale")
        _ = makeCoordinator()
        XCTAssertTrue(makeCoordinator().hasCompletedCurrentOnboarding)

        // 移除证据并模拟再次初始化：migration 标记已存在，不再改写
        defaults.removeObject(forKey: "petScale")
        _ = makeCoordinator()
        XCTAssertTrue(makeCoordinator().hasCompletedCurrentOnboarding)
    }

    // MARK: - Bubble priority resolver

    func testBubblePriorityResolver() {
        // maintenance + guide → maintenance（引导不能改变任务气泡的尺寸/显示）
        XCTAssertEqual(
            PetAuxiliaryBubbleResolver.resolve(
                hasMaintenanceTask: true,
                urgentReminderVisible: false,
                activeGuide: sampleGuide(),
                showsMusicLyric: false,
                ambientMessageVisible: false,
                showsStatusBubble: false
            ),
            .maintenance
        )
        // urgent + guide → urgent
        XCTAssertEqual(
            PetAuxiliaryBubbleResolver.resolve(
                hasMaintenanceTask: false,
                urgentReminderVisible: true,
                activeGuide: sampleGuide(),
                showsMusicLyric: false,
                ambientMessageVisible: false,
                showsStatusBubble: true
            ),
            .urgentStatus
        )
        // guide + lyric → guide
        XCTAssertEqual(
            PetAuxiliaryBubbleResolver.resolve(
                hasMaintenanceTask: false,
                urgentReminderVisible: false,
                activeGuide: sampleGuide(),
                showsMusicLyric: true,
                ambientMessageVisible: false,
                showsStatusBubble: false
            ),
            .guide
        )
        // lyric + ambient → lyric
        XCTAssertEqual(
            PetAuxiliaryBubbleResolver.resolve(
                hasMaintenanceTask: false,
                urgentReminderVisible: false,
                activeGuide: nil,
                showsMusicLyric: true,
                ambientMessageVisible: true,
                showsStatusBubble: false
            ),
            .musicLyric
        )
        // ambient + status → ambient
        XCTAssertEqual(
            PetAuxiliaryBubbleResolver.resolve(
                hasMaintenanceTask: false,
                urgentReminderVisible: false,
                activeGuide: nil,
                showsMusicLyric: false,
                ambientMessageVisible: true,
                showsStatusBubble: true
            ),
            .ambient
        )
        // 空 → none
        XCTAssertEqual(
            PetAuxiliaryBubbleResolver.resolve(
                hasMaintenanceTask: false,
                urgentReminderVisible: false,
                activeGuide: nil,
                showsMusicLyric: false,
                ambientMessageVisible: false,
                showsStatusBubble: false
            ),
            .none
        )
    }

    private func sampleGuide() -> PetGuide {
        PetGuide(id: "sample", message: "sample")
    }
}
