import Foundation
import XCTest
@testable import YuanGUI

@MainActor
final class FakeTrashHandler: TrashHandling {
    var recycled: [URL] = []
    var recycleResult = 0
    var opened = false
    var emptied = false

    func recycle(_ urls: [URL]) async throws -> Int {
        recycled = urls
        return recycleResult
    }

    func openTrash() { opened = true }
    func emptyTrash() throws { emptied = true }
}

@MainActor
final class FakeDesktopIconManager: DesktopIconManaging {
    var visible: Bool
    private(set) var requestedVisibility: Bool?

    init(visible: Bool) {
        self.visible = visible
    }

    func areDesktopIconsVisible() -> Bool { visible }

    func setDesktopIconsVisible(_ visible: Bool) throws {
        requestedVisibility = visible
        self.visible = visible
    }
}

@MainActor
final class PetStoreTests: XCTestCase {
    func testFreshStoreDefaultsToDuo() {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )

        XCTAssertEqual(store.mode, .duo)
        XCTAssertEqual(store.petScale, PetLayout.defaultScale)
        XCTAssertTrue(store.petMotionEnabled)
        XCTAssertTrue(store.ambientChatterEnabled)
        XCTAssertEqual(store.ambientChatterIntervalMinutes, 15)
        XCTAssertTrue(store.weatherAnnouncementsEnabled)
    }

    func testDynamicIdleStaysOnBreathingSequenceWhileStaticModeRotatesArtwork() {
        let suite = "PetStoreDynamicIdleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setBedtimeReminderEnabled(false)
        store.setPetPresented(true)
        store.interact()
        XCTAssertNotEqual(store.actionIndex, 0)

        store.chooseIdleAction()
        XCTAssertEqual(store.actionIndex, 0)

        store.setPetMotionEnabled(false)
        store.chooseIdleAction()
        XCTAssertEqual(store.actionIndex, 1)
    }

    func testFocusModeSuppressesNonUrgentBubblesButKeepsUrgentWarnings() {
        let suite = "PetStoreFocusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setBedtimeReminderEnabled(false)
        store.setPetPresented(true)
        store.setSystemStatusVisible(true)
        store.applySmartStates([.rainy])
        store.beginFocus()

        XCTAssertTrue(store.isFocusActive)
        XCTAssertFalse(store.shouldShowPetBubble)
        store.showAmbientMessage("不应该出现")
        XCTAssertNil(store.ambientMessage)

        store.applySmartStates([.memoryPressure])
        XCTAssertTrue(store.shouldShowPetBubble)
        store.endFocus(completed: true)
        XCTAssertTrue(store.isFocusCelebrating)
        XCTAssertEqual(store.currentAction.file, "19-maintenance-success")
    }

    func testAutomaticChatterUsesChatActionWhileAIChatKeepsItsStaticChatPose() {
        let suite = "PetStoreSpeakingActionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setPetPresented(true)

        store.showAmbientMessage("天气播报")
        XCTAssertEqual(store.currentAction.file, "14-chatting")
        XCTAssertNotNil(store.ambientMessage)

        store.dismissAmbientMessage()
        store.interact()
        let staticAction = store.currentAction
        let staticScale = store.petScale
        store.setPetMotionEnabled(false)
        store.showAmbientMessage("关闭动画后的天气播报")
        XCTAssertEqual(store.currentAction, staticAction)
        XCTAssertEqual(store.petScale, staticScale)

        store.dismissAmbientMessage()
        store.setChatting(true)
        XCTAssertEqual(store.currentAction.file, "14-chatting")
        XCTAssertNil(store.ambientMessage)
    }

    func testMotionToggleSelectsAnimatedIdleWithoutChangingPetScale() {
        let suite = "PetStoreMotionToggleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setBedtimeReminderEnabled(false)
        store.setPetPresented(true)
        store.setPetScale(1.1)
        store.setPetMotionEnabled(false)
        store.interact()
        let actionIndex = store.actionIndex

        store.setPetMotionEnabled(true)

        XCTAssertNotEqual(actionIndex, 0)
        XCTAssertEqual(store.actionIndex, 0)
        XCTAssertEqual(store.petScale, 1.1)
    }

    func testDesktopIconStateIsReadAndToggledThroughFinderManager() {
        let suite = "PetStoreDesktopIconTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let desktopIcons = FakeDesktopIconManager(visible: false)
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            desktopIconManager: desktopIcons,
            defaults: defaults,
            startServices: false
        )

        XCTAssertFalse(store.desktopIconsVisible)

        store.toggleDesktopIcons()

        XCTAssertEqual(desktopIcons.requestedVisibility, true)
        XCTAssertTrue(store.desktopIconsVisible)
        XCTAssertEqual(store.toast, "已显示桌面图标")
    }

    func testAmbientChatterPreferencesClampAndPersist() {
        let suite = "PetStoreChatterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        store.setAmbientChatterEnabled(false)
        store.setAmbientChatterIntervalMinutes(2)
        store.setWeatherAnnouncementsEnabled(false)
        XCTAssertFalse(store.ambientChatterEnabled)
        XCTAssertEqual(store.ambientChatterIntervalMinutes, 2)
        XCTAssertFalse(store.weatherAnnouncementsEnabled)

        store.setAmbientChatterIntervalMinutes(0)
        XCTAssertEqual(store.ambientChatterIntervalMinutes, 1)

        store.setAmbientChatterIntervalMinutes(200)
        XCTAssertEqual(store.ambientChatterIntervalMinutes, 120)
        XCTAssertFalse(defaults.bool(forKey: "ambientChatterEnabled"))
        XCTAssertEqual(defaults.integer(forKey: "ambientChatterIntervalMinutes"), 120)
        XCTAssertFalse(defaults.bool(forKey: "weatherAnnouncementsEnabled"))
    }

    func testDashboardKeepsRoomForReadableBottomActions() {
        XCTAssertGreaterThanOrEqual(MenuBarDashboardView.preferredWidth, 400)
    }

    func testRecycleUsesInjectedHandlerWithoutTouchingFilesystem() async {
        let fake = FakeTrashHandler()
        fake.recycleResult = 2
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )
        let urls = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]

        await store.recycleItems(urls)

        XCTAssertEqual(fake.recycled, urls)
        XCTAssertEqual(store.toast, "已将 2 个项目移入废纸篓")
    }

    func testModeAndStatusPersist() {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )

        store.setMode(.vcc)
        store.setSystemStatusVisible(true)
        store.setDashboardStyle(.midnight)
        store.setIdleAnimationEnabled(false)
        store.setPetMotionEnabled(false)

        XCTAssertEqual(defaults.integer(forKey: "petMode"), PetMode.vcc.rawValue)
        XCTAssertTrue(defaults.bool(forKey: "showsSystemStatus"))
        XCTAssertEqual(defaults.integer(forKey: "dashboardStyle"), DashboardStyle.midnight.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "idleAnimationEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "petMotionEnabled"))
    }

    func testHiddenPetSuppressesAmbientMessagesAndClearsVisibleMessage() {
        let suite = "PetStorePresentationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        store.showAmbientMessage("隐藏时不显示")
        XCTAssertNil(store.ambientMessage)

        store.setPetPresented(true)
        store.showAmbientMessage("显示时出现")
        XCTAssertEqual(store.ambientMessage, "显示时出现")

        store.setPetPresented(false)
        XCTAssertNil(store.ambientMessage)
    }

    func testInteractionKeepsSystemStatusVisible() {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )

        store.setSystemStatusVisible(true)
        store.interact()

        XCTAssertTrue(store.showsSystemStatus)
    }

    func testInteractionLockPersistsAndPreventsActionChange() {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )

        store.setInteractionLocked(true)
        let action = store.actionIndex
        store.interact()

        XCTAssertTrue(store.interactionLocked)
        XCTAssertTrue(store.lockedControlsVisible)
        XCTAssertTrue(defaults.bool(forKey: "interactionLocked"))
        XCTAssertEqual(store.actionIndex, action)

        store.setInteractionLocked(false)
        XCTAssertFalse(store.lockedControlsVisible)
    }

    func testLockedControlsCanAutoHideAndBeRevealed() async throws {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )

        store.setInteractionLocked(true)
        store.scheduleLockedControlsHide(after: 0)
        try await Task.sleep(nanoseconds: 2_000_000)
        XCTAssertFalse(store.lockedControlsVisible)

        store.revealLockedControls()
        XCTAssertTrue(store.lockedControlsVisible)
    }

    func testAutomaticBedtimeBubbleCanBeClosedAndSettingsPersist() {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = SystemMonitor(coordinator: MetricsCoordinator(readers: []))
        let store = PetStore(
            monitor: monitor,
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )
        let hour = Calendar.current.component(.hour, from: Date())
        store.setBedtimeStartMinutes(hour * 60)
        store.setBedtimeEndMinutes(((hour + 1) % 24) * 60)
        store.setBedtimeReminderEnabled(true)

        XCTAssertTrue(store.shouldShowPetBubble)
        monitor.setPetVisible(true)
        XCTAssertEqual(monitor.profile, .live, "自动出现的监控栏也必须声明实时 CPU 采样需求")
        store.toggleSystemStatus()
        XCTAssertFalse(store.shouldShowPetBubble)
        XCTAssertEqual(monitor.profile, .companion)
        XCTAssertTrue(store.automaticBubbleSuppressed)
        XCTAssertEqual(defaults.integer(forKey: "bedtimeStartMinutes"), hour * 60)

        store.setBedtimeReminderEnabled(false)
        XCTAssertFalse(store.activeSmartStates.contains(.bedtime))
    }

    func testPetScaleClampsAndPersists() {
        let fake = FakeTrashHandler()
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: fake,
            defaults: defaults,
            startServices: false
        )

        store.setPetScale(2)
        XCTAssertEqual(store.petScale, 1.4)
        XCTAssertEqual(defaults.double(forKey: "petScale"), 1.4)
        store.setPetScale(0.2)
        XCTAssertEqual(store.petScale, 0.5)
    }

    func testMiniPetScalesItsStatusBubbleAndPanel() {
        XCTAssertEqual(PetLayout.compactBubbleScale(scale: 0.50), 0.82, accuracy: 0.001)
        XCTAssertEqual(PetLayout.compactBubbleScale(scale: 0.60), 0.91, accuracy: 0.001)
        XCTAssertEqual(PetLayout.compactBubbleScale(scale: 0.70), 1.00, accuracy: 0.001)
        XCTAssertEqual(PetLayout.statusBubbleWidth(scale: 0.50), 260, accuracy: 0.001)
        XCTAssertEqual(PetLayout.statusBubbleWidth(scale: 0.60), 296, accuracy: 0.001)
        XCTAssertEqual(PetLayout.ambientBubbleWidth(scale: 0.50), 240, accuracy: 0.001)

        let mini = PetLayout.panelSize(scale: 0.50, showsBubble: true)
        let small = PetLayout.panelSize(scale: 0.70, showsBubble: true)
        XCTAssertEqual(mini.width, PetLayout.minimumBubbleWidth, accuracy: 0.001)
        XCTAssertLessThan(mini.height, small.height)
    }

    func testCompactPetCanUseTransparentTopInsetButBubblesStayVisible() {
        XCTAssertEqual(
            PetLayout.allowedTopOverflow(scale: 1, showsBubble: false, showsChat: false, showsMaintenance: false),
            PetLayout.compactTopTransparentInset
        )
        XCTAssertEqual(
            PetLayout.allowedTopOverflow(scale: 1, showsBubble: true, showsChat: false, showsMaintenance: false),
            0
        )
        XCTAssertEqual(
            PetLayout.allowedTopOverflow(scale: 1, showsBubble: false, showsChat: true, showsMaintenance: false),
            0
        )
    }

    func testBottomToolbarPanelSizeMatchesItsFiveButtons() {
        XCTAssertEqual(PetLayout.bottomToolbarPanelSize.width, 160)
        XCTAssertEqual(PetLayout.bottomToolbarPanelSize.height, 70)
        XCTAssertEqual(PetLayout.lockedControlPanelSize.width, 48)
        XCTAssertEqual(PetLayout.lockedControlPanelSize.height, 48)
    }

    func testPanelResizePreservesPetVisualAnchor() {
        let oldPanel = CGRect(x: 320, y: 180, width: 405, height: 292.5)
        let oldVisual = PetLayout.petVisualFrame(
            panelFrame: oldPanel,
            scale: 0.75,
            showsChat: false
        )
        let targetSize = PetLayout.panelSize(
            scale: 0.75,
            showsBubble: false,
            showsChat: true
        )
        let origin = PetLayout.panelOrigin(
            preservingPetVisualFrame: oldVisual,
            targetPanelSize: targetSize,
            scale: 0.75,
            showsChat: true
        )
        let resizedVisual = PetLayout.petVisualFrame(
            panelFrame: CGRect(origin: origin, size: targetSize),
            scale: 0.75,
            showsChat: true
        )

        XCTAssertEqual(resizedVisual.minX, oldVisual.minX, accuracy: 0.001)
        XCTAssertEqual(resizedVisual.minY, oldVisual.minY, accuracy: 0.001)
    }

    func testAuxiliaryBubbleFlipsBelowPetNearTopEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let pet = CGRect(x: 700, y: 500, width: 240, height: 280)
        let bubble = CGSize(width: 350, height: 120)
        let origin = PetLayout.auxiliaryBubbleOrigin(
            petVisualFrame: pet,
            bubbleSize: bubble,
            visibleFrame: visible
        )

        XCTAssertLessThanOrEqual(
            origin.y + bubble.height,
            pet.minY - PetLayout.auxiliaryBubbleSpacing
        )
        XCTAssertGreaterThanOrEqual(origin.x, visible.minX)
        XCTAssertLessThanOrEqual(origin.x + bubble.width, visible.maxX)
    }

    func testAuxiliaryBubbleOverlapsOnlyTheSpritesTransparentTopInset() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let pet = CGRect(x: 460, y: 160, width: 245, height: 245)
        let bubble = CGSize(width: 350, height: 120)
        let origin = PetLayout.auxiliaryBubbleOrigin(
            petVisualFrame: pet,
            bubbleSize: bubble,
            visibleFrame: visible
        )

        XCTAssertEqual(
            origin.y,
            pet.maxY + PetLayout.auxiliaryBubbleSpacing,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(origin.y + bubble.height, pet.maxY)
    }

    func testDefaultAndCompactControlScales() {
        XCTAssertEqual(PetLayout.defaultScale, 0.75)
        XCTAssertTrue(PetLayout.usesCompactControls(scale: 0.50))
        XCTAssertTrue(PetLayout.usesCompactControls(scale: 0.60))
        XCTAssertFalse(PetLayout.usesCompactControls(scale: 0.70))
        XCTAssertFalse(PetLayout.usesCompactControls(scale: PetLayout.defaultScale))
    }

    func testCompactSideControlsDoNotOverlapBottomToolbar() {
        for scale in [0.50, 0.60] {
            let panel = PetLayout.panelSize(scale: scale, showsBubble: true)
            XCTAssertGreaterThanOrEqual(
                PetLayout.compactControlsGapFromToolbar(panelWidth: panel.width),
                8,
                "Compact controls overlap at \(scale) scale"
            )
        }
    }

    func testMaintenanceBubbleHasSpaceForGroupedResults() {
        let normal = PetLayout.panelSize(scale: PetLayout.defaultScale, showsBubble: false)
        let maintenance = PetLayout.panelSize(
            scale: PetLayout.defaultScale,
            showsBubble: false,
            showsMaintenance: true
        )
        XCTAssertGreaterThanOrEqual(maintenance.width, 450)
        XCTAssertEqual(maintenance.height - normal.height, PetLayout.maintenanceHeight)
        XCTAssertGreaterThanOrEqual(PetLayout.maintenanceHeight, 340)
    }

    func testEdgeDockingDetectsEveryScreenSideAndIgnoresCenter() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = CGSize(width: 326, height: 326)

        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: -170, y: 200), size: size), in: visible), .left)
        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: 1_280, y: 200), size: size), in: visible), .right)
        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: 400, y: 740), size: size), in: visible), .top)
        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: 400, y: -170), size: size), in: visible), .bottom)
        XCTAssertNil(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: 400, y: 250), size: size), in: visible))
        XCTAssertNil(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: -150, y: 250), size: size), in: visible))
    }

    func testPetVisualFrameMatchesRenderedImageArea() {
        let panel = CGRect(x: 100, y: 200, width: 540, height: 390)
        let pet = PetLayout.petVisualFrame(panelFrame: panel, scale: 1, showsChat: false)
        XCTAssertEqual(pet.size, CGSize(width: 326, height: 326))
        XCTAssertEqual(pet.midX, panel.midX + 35)
        XCTAssertEqual(pet.minY, panel.minY)
    }

    func testEdgePeekAndExpandedOriginsStayVisible() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let panelSize = CGSize(width: 540, height: 390)
        let anchor = CGRect(origin: CGPoint(x: -20, y: 700), size: panelSize)

        for edge in PetDockEdge.allCases {
            let peek = PetLayout.edgePeekOrigin(edge: edge, anchorFrame: anchor, visibleFrame: visible)
            let peekFrame = CGRect(origin: peek, size: PetLayout.edgePeekSize)
            XCTAssertTrue(visible.contains(peekFrame))

            let expanded = PetLayout.expandedOrigin(
                edge: edge,
                previousOrigin: anchor.origin,
                panelSize: panelSize,
                visibleFrame: visible,
                allowedTopOverflow: 58
            )
            XCTAssertGreaterThanOrEqual(expanded.x, visible.minX)
            XCTAssertGreaterThanOrEqual(expanded.y, visible.minY)
            XCTAssertLessThanOrEqual(expanded.x + panelSize.width, visible.maxX)
            XCTAssertLessThanOrEqual(expanded.y + panelSize.height, visible.maxY + 58)
        }
    }

    func testEdgePeekSpriteFitsInsideItsCircle() {
        XCTAssertLessThan(PetLayout.edgePeekSpriteSize, PetLayout.edgePeekButtonDiameter)
        XCTAssertLessThanOrEqual(
            PetLayout.edgePeekSpriteSize,
            PetLayout.edgePeekButtonDiameter - 4
        )
    }

    func testSmartStatePrioritizesPressureAndLowBattery() {
        var snapshot = SystemSnapshot.empty
        snapshot.battery = BatteryMetrics(
            isPresent: true,
            chargeFraction: 0.15,
            isCharging: false,
            powerSource: .battery,
            timeRemainingMinutes: 20
        )
        XCTAssertEqual(SmartPetState.resolve(from: snapshot), .lowBattery)

        snapshot.battery = BatteryMetrics(
            isPresent: true,
            chargeFraction: 0.15,
            isCharging: true,
            powerSource: .ac,
            timeRemainingMinutes: nil
        )
        XCTAssertEqual(SmartPetState.resolve(from: snapshot), .charging)

        snapshot.memory = MemoryMetrics(
            total: 100,
            used: 95,
            free: 5,
            active: 50,
            inactive: 10,
            wired: 20,
            compressed: 15,
            cached: 0,
            swapUsed: 0,
            swapTotal: 0,
            pressure: .critical
        )
        XCTAssertEqual(SmartPetState.resolve(from: snapshot), .memoryPressure)
    }

    func testNewChargingStateImmediatelyInterruptsIdleAction() {
        let suite = "PetStoreChargingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setBedtimeReminderEnabled(false)

        XCTAssertTrue(store.currentAction.file.contains("idle"))

        store.applySmartStates([.charging])

        XCTAssertEqual(store.smartState, .charging)
        XCTAssertEqual(store.currentAction.file, "11-charging")
    }

    func testNewSmartStateCancelsManualActionSuppression() {
        let suite = "PetStoreSmartTransitionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        store.applySmartStates([.rainy])
        store.interact()
        XCTAssertNotEqual(store.currentAction.file, "12-rainy")

        store.applySmartStates([.rainy, .charging])

        XCTAssertEqual(store.smartState, .charging)
        XCTAssertEqual(store.currentAction.file, "11-charging")
    }

    func testMemoryAlertStartsAtNinetyPercentOrCriticalPressure() {
        var snapshot = SystemSnapshot.empty
        snapshot.memory = MemoryMetrics(
            total: 100,
            used: 89,
            free: 11,
            active: 50,
            inactive: 10,
            wired: 20,
            compressed: 9,
            cached: 0,
            swapUsed: 0,
            swapTotal: 0,
            pressure: .warning
        )

        XCTAssertEqual(SmartPetState.resolve(from: snapshot), .normal)
        XCTAssertFalse(
            PetStatusMessageResolver.message(snapshot: snapshot, smartState: .normal)
                .contains("内存占用有些高")
        )

        snapshot.memory = MemoryMetrics(
            total: 100,
            used: 90,
            free: 10,
            active: 50,
            inactive: 10,
            wired: 20,
            compressed: 10,
            cached: 0,
            swapUsed: 0,
            swapTotal: 0,
            pressure: .warning
        )
        XCTAssertEqual(SmartPetState.resolve(from: snapshot), .memoryPressure)
        XCTAssertTrue(
            PetStatusMessageResolver.message(snapshot: snapshot, smartState: .normal)
                .contains("90%")
        )

        snapshot.memory = MemoryMetrics(
            total: 100,
            used: 70,
            free: 30,
            active: 30,
            inactive: 10,
            wired: 20,
            compressed: 10,
            cached: 0,
            swapUsed: 0,
            swapTotal: 0,
            pressure: .critical
        )
        XCTAssertEqual(SmartPetState.resolve(from: snapshot), .memoryPressure)

        snapshot.memory = nil
        snapshot.cpu = CPUMetrics(total: 0.91, user: 0.65, system: 0.26)
        let cpuMessage = PetStatusMessageResolver.message(snapshot: snapshot, smartState: .normal)
        XCTAssertTrue(cpuMessage.contains("CPU 现在有点忙"))
        XCTAssertTrue(cpuMessage.contains("91%"))
    }

    func testListeningOutranksPersistentNonUrgentStateAfterTransientPresentation() {
        let mode = PetMode.duo
        let listening = PetActionResolver.resolve(PetActionContext(
            mode: mode,
            taskState: .idle,
            actionIndex: 0,
            isChatting: false,
            isFocusActive: false,
            isFocusCelebrating: false,
            isMusicPlaying: true,
            petMotionEnabled: true,
            ambientMessageVisible: false,
            smartReactionsEnabled: true,
            smartActionSuppressed: false,
            smartState: .rainy,
            transientSmartState: nil
        ))
        let transientRain = PetActionResolver.resolve(PetActionContext(
            mode: mode,
            taskState: .idle,
            actionIndex: 0,
            isChatting: false,
            isFocusActive: false,
            isFocusCelebrating: false,
            isMusicPlaying: true,
            petMotionEnabled: true,
            ambientMessageVisible: false,
            smartReactionsEnabled: true,
            smartActionSuppressed: false,
            smartState: .rainy,
            transientSmartState: .rainy
        ))

        XCTAssertEqual(listening, mode.musicAction)
        XCTAssertEqual(transientRain, mode.smartAction(for: .rainy))
    }

    func testUrgentStateAlwaysOutranksListening() {
        let mode = PetMode.duo
        let action = PetActionResolver.resolve(PetActionContext(
            mode: mode,
            taskState: .idle,
            actionIndex: 0,
            isChatting: false,
            isFocusActive: false,
            isFocusCelebrating: false,
            isMusicPlaying: true,
            petMotionEnabled: true,
            ambientMessageVisible: false,
            smartReactionsEnabled: true,
            smartActionSuppressed: true,
            smartState: .memoryPressure,
            transientSmartState: nil
        ))

        XCTAssertEqual(action, mode.smartAction(for: .memoryPressure))
    }

    func testAmbientChatterUsesWeatherAndChargingEstimate() {
        var snapshot = SystemSnapshot.empty
        snapshot.battery = BatteryMetrics(
            isPresent: true,
            chargeFraction: 0.54,
            isCharging: true,
            powerSource: .ac,
            timeRemainingMinutes: 90
        )
        let weather = WeatherSnapshot(
            temperature: 32,
            apparentTemperature: 36,
            relativeHumidity: 68,
            windSpeed: 14,
            weatherCode: 3,
            isDay: true,
            updatedAt: Date()
        )

        let messages = PetAmbientChatter.candidates(mode: .duo, system: snapshot, weather: weather)

        XCTAssertTrue(messages.contains { $0.contains("32°") && $0.contains("阴天") && $0.contains("14 km/h") })
        XCTAssertTrue(messages.contains { $0.contains("1小时30分钟") && $0.contains("充电") })
        XCTAssertTrue(messages.contains { $0.contains("元圭") && $0.contains("VCC") })
    }

    func testAmbientChatterUsesCityAndBatteryRuntimeForEveryVoice() {
        var snapshot = SystemSnapshot.empty
        snapshot.battery = BatteryMetrics(
            isPresent: true,
            chargeFraction: 0.72,
            isCharging: false,
            powerSource: .battery,
            timeRemainingMinutes: 192
        )

        for mode in PetMode.allCases {
            let messages = PetAmbientChatter.candidates(
                mode: mode,
                system: snapshot,
                weather: nil,
                locationName: "上海市"
            )
            XCTAssertTrue(messages.contains { $0.contains("上海市") })
            XCTAssertTrue(messages.contains { $0.contains("3小时12分钟") })
        }
        let vcc = PetAmbientChatter.candidates(
            mode: .vcc,
            system: snapshot,
            weather: nil,
            locationName: "上海市"
        )
        XCTAssertTrue(vcc.contains { $0.contains("罐头") })
        XCTAssertTrue(vcc.contains { $0.contains("喵喵喵") && $0.contains("预计还能使用") })
    }

    func testWeatherAnnouncementsCoverRainHeatColdAndVoice() {
        func weather(temperature: Double, apparent: Double, code: Int) -> WeatherSnapshot {
            WeatherSnapshot(
                temperature: temperature,
                apparentTemperature: apparent,
                relativeHumidity: 70,
                windSpeed: 6,
                weatherCode: code,
                isDay: true,
                updatedAt: Date()
            )
        }

        let rain = PetAmbientChatter.weatherAnnouncements(
            mode: .duo,
            weather: weather(temperature: 24, apparent: 26, code: 61),
            locationName: "杭州市"
        )
        XCTAssertTrue(rain.allSatisfy { $0.contains("雨") })
        XCTAssertTrue(rain.contains { $0.contains("杭州市") && $0.contains("喵喵喵") })

        let hot = PetAmbientChatter.weatherAnnouncements(
            mode: .vcc,
            weather: weather(temperature: 32, apparent: 36, code: 1)
        )
        XCTAssertTrue(hot.contains { $0.contains("热") && $0.contains("VCC") })

        let cold = PetAmbientChatter.weatherAnnouncements(
            mode: .yuanGui,
            weather: weather(temperature: 6, apparent: 4, code: 2)
        )
        XCTAssertTrue(cold.contains { $0.contains("冷") && $0.contains("元圭") })
    }

    func testAmbientMessageReservesBubbleSpaceWithoutChangingMonitorPreference() {
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        store.setBedtimeReminderEnabled(false)
        store.setSmartReactionsEnabled(false)
        store.setPetPresented(true)

        XCTAssertFalse(store.shouldShowPetBubble)
        store.showAmbientMessage("元圭和 VCC 来陪你啦～", duration: 60)
        XCTAssertEqual(store.ambientMessage, "元圭和 VCC 来陪你啦～")
        XCTAssertTrue(store.shouldReservePetBubbleSpace)
        XCTAssertFalse(store.showsSystemStatus)

        store.dismissAmbientMessage()
        XCTAssertNil(store.ambientMessage)
        XCTAssertFalse(store.shouldReservePetBubbleSpace)
    }

    func testUrgentAlertKindsAndReminderModePersistIndependently() {
        let suite = "PetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        store.setLowBatteryAlertsEnabled(false)
        store.applySmartStates([.lowBattery, .memoryPressure])
        XCTAssertEqual(store.activeSmartStates, [.memoryPressure])

        store.setMemoryPressureAlertsEnabled(false)
        store.applySmartStates([.lowBattery, .memoryPressure])
        XCTAssertTrue(store.activeSmartStates.isEmpty)

        store.setUrgentReminderMode(.interval)
        store.setUrgentReminderIntervalMinutes(25)
        XCTAssertEqual(defaults.string(forKey: "urgentReminderMode"), UrgentReminderMode.interval.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "urgentReminderIntervalMinutes"), 25)
    }
}
