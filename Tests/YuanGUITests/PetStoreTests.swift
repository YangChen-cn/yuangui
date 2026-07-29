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
    func testChatterPeriodBoundariesUseExpectedTimeBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        func date(hour: Int, minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 29,
                hour: hour,
                minute: minute
            )))
        }

        XCTAssertEqual(PetChatterPeriod.resolve(at: try date(hour: 5), calendar: calendar), .morning)
        XCTAssertEqual(PetChatterPeriod.resolve(at: try date(hour: 11, minute: 59), calendar: calendar), .morning)
        XCTAssertEqual(PetChatterPeriod.resolve(at: try date(hour: 12), calendar: calendar), .afternoon)
        XCTAssertEqual(PetChatterPeriod.resolve(at: try date(hour: 18), calendar: calendar), .evening)
        XCTAssertEqual(PetChatterPeriod.resolve(at: try date(hour: 22), calendar: calendar), .lateNight)
        XCTAssertEqual(PetChatterPeriod.resolve(at: try date(hour: 4, minute: 59), calendar: calendar), .lateNight)
    }

    func testChatterSelectorAvoidsFiveRecentIDsAndReleasesOldestWhenNeeded() {
        let candidates = (0..<6).map {
            PetChatterCandidate(id: "line-\($0)", text: "Line \($0)")
        }
        XCTAssertEqual(
            PetChatterSelector.eligible(
                from: candidates,
                recentIDs: Array(candidates[1...5].map(\.id))
            ).map(\.id),
            ["line-0"]
        )

        let exhausted = Array(candidates.prefix(2))
        XCTAssertEqual(
            PetChatterSelector.eligible(
                from: exhausted,
                recentIDs: exhausted.map(\.id)
            ).map(\.id),
            ["line-0"]
        )
        XCTAssertEqual(
            PetChatterSelector.recording("line-6", in: candidates.prefix(6).map(\.id)),
            ["line-2", "line-3", "line-4", "line-5", "line-6"]
        )
    }

    func testAmbientChatterIncludesCurrentPeriodForEveryCompanionMode() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 29,
            hour: 8
        )))

        for mode in PetMode.allCases {
            let candidates = PetAmbientChatter.candidateEntries(
                mode: mode,
                system: .empty,
                weather: nil,
                date: morning,
                calendar: calendar
            )
            XCTAssertTrue(candidates.contains { $0.id.contains(".morning.") })
        }
    }

    func testDiarySavedMessagesAreDistinctForEveryPetMode() {
        let yuanGuiMessages = Set(PetStore.diarySavedMessages(for: .yuanGui))
        let vccMessages = Set(PetStore.diarySavedMessages(for: .vcc))
        let duoMessages = Set(PetStore.diarySavedMessages(for: .duo))

        XCTAssertFalse(yuanGuiMessages.isEmpty)
        XCTAssertFalse(vccMessages.isEmpty)
        XCTAssertFalse(duoMessages.isEmpty)
        XCTAssertTrue(yuanGuiMessages.isDisjoint(with: vccMessages))
        XCTAssertTrue(yuanGuiMessages.isDisjoint(with: duoMessages))
        XCTAssertTrue(vccMessages.isDisjoint(with: duoMessages))
    }

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
        store.setBedtimeReminderEnabled(false)
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
        XCTAssertEqual(store.toast, AppLocalizer.string("已显示桌面图标"))
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

    func testFreshStoreDefaultsToLiquidGlassDashboardStyle() {
        let suite = "PetStoreDashboardStyleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        XCTAssertEqual(store.dashboardStyle, .liquidGlass)
        XCTAssertNil(defaults.object(forKey: "dashboardStyle"))
        XCTAssertTrue(defaults.bool(forKey: PetStore.liquidGlassThemeMigrationKey))
    }

    func testUpgradeForcesLiquidGlassOnceThenPreservesLaterThemeChoice() {
        let suite = "PetStoreDashboardStyleMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(DashboardStyle.midnight.rawValue, forKey: "dashboardStyle")

        let upgraded = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        XCTAssertEqual(upgraded.dashboardStyle, .liquidGlass)
        XCTAssertEqual(
            defaults.integer(forKey: "dashboardStyle"),
            DashboardStyle.liquidGlass.rawValue
        )
        XCTAssertTrue(defaults.bool(forKey: PetStore.liquidGlassThemeMigrationKey))

        upgraded.setDashboardStyle(.mint)
        let relaunched = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
        XCTAssertEqual(relaunched.dashboardStyle, .mint)
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
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while store.lockedControlsVisible, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
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

    func testAuxiliaryBubbleFollowsPetAcrossSpaces() {
        let behavior = PetPanelController.auxiliaryBubbleCollectionBehavior
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
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

    func testChatResizeClampsWholePanelWhenPetIsParkedAtDisplayEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let usable = PetLayout.usablePanelFrame(in: visible, showsChat: true)
        let targetSize = PetLayout.panelSize(scale: 0.75, showsBubble: false, showsChat: true)
        for x in [visible.minX, visible.maxX - 405] {
            let resized = PetLayout.resizedPanelFrame(
                from: CGRect(x: x, y: visible.minY, width: 405, height: 292.5),
                targetSize: targetSize,
                scale: 0.75,
                oldShowsChat: false,
                newShowsChat: true,
                visibleFrame: usable
            )
            XCTAssertGreaterThanOrEqual(resized.minX, usable.minX)
            XCTAssertLessThanOrEqual(resized.maxX, usable.maxX)
            XCTAssertGreaterThanOrEqual(resized.minY, usable.minY)
            XCTAssertLessThanOrEqual(resized.maxY, usable.maxY)
        }
    }

    func testClosingChatRestoresOriginalPetAnchorAtDisplayEdges() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let compactSize = PetLayout.panelSize(
            scale: 0.75,
            showsBubble: false,
            showsChat: false
        )
        let originalOrigins = [
            CGPoint(x: visible.minX - 80, y: 120),
            CGPoint(x: visible.maxX - compactSize.width + 80, y: 120),
            CGPoint(x: 240, y: visible.minY - 80),
            CGPoint(x: 240, y: visible.maxY - compactSize.height + 80)
        ]

        for originalOrigin in originalOrigins {
            let restoredOrigin = PetLayout.restoredCompactOrigin(
                originalOrigin,
                panelSize: compactSize,
                scale: 0.75,
                visibleFrame: visible,
            )
            XCTAssertEqual(restoredOrigin.x, originalOrigin.x, accuracy: 0.001)
            XCTAssertEqual(restoredOrigin.y, originalOrigin.y, accuracy: 0.001)
        }
    }

    func testChatClosePullsPetBackOnlyWhenCharacterWouldBeInvisible() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let compactSize = PetLayout.panelSize(
            scale: 0.75,
            showsBubble: false,
            showsChat: false
        )
        let restored = PetLayout.restoredCompactOrigin(
            CGPoint(x: -2_000, y: 120),
            panelSize: compactSize,
            scale: 0.75,
            visibleFrame: visible
        )

        XCTAssertGreaterThanOrEqual(restored.x, visible.minX)
        XCTAssertGreaterThanOrEqual(restored.y, visible.minY)
    }

    func testCompactPanelConstraintKeepsTransparentMarginsOutsideScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let scale = 0.75
        let compactSize = PetLayout.panelSize(
            scale: scale,
            showsBubble: false,
            showsChat: false
        )
        let overflow = PetLayout.compactHorizontalOverflow(scale: scale)
        let rightEdgeOrigin = CGPoint(
            x: visible.maxX - compactSize.width + overflow.right,
            y: 120
        )
        let constrained = PetLayout.constrainedOrigin(
            rightEdgeOrigin,
            panelSize: compactSize,
            visibleFrame: visible,
            allowedTopOverflow: PetLayout.compactTopTransparentInset * scale,
            allowedLeftOverflow: overflow.left,
            allowedRightOverflow: overflow.right
        )

        XCTAssertEqual(constrained.x, rightEdgeOrigin.x, accuracy: 0.001)
        XCTAssertGreaterThan(
            CGRect(origin: constrained, size: compactSize).maxX,
            visible.maxX
        )
        XCTAssertEqual(
            PetLayout.petVisualFrame(
                panelFrame: CGRect(origin: constrained, size: compactSize),
                scale: scale,
                showsChat: false
            ).maxX,
            visible.maxX,
            accuracy: 0.001
        )
    }

    func testChatUsableFrameKeepsComposerAwayFromScreenEdges() {
        let visible = CGRect(x: -600, y: 24, width: 600, height: 900)
        let usable = PetLayout.usablePanelFrame(in: visible, showsChat: true)
        XCTAssertEqual(usable.minX, visible.minX + PetLayout.chatScreenEdgeInset)
        XCTAssertEqual(usable.minY, visible.minY + PetLayout.chatScreenEdgeInset)
        XCTAssertEqual(usable.maxX, visible.maxX - PetLayout.chatScreenEdgeInset)
        XCTAssertEqual(usable.maxY, visible.maxY - PetLayout.chatScreenEdgeInset)
        XCTAssertEqual(PetLayout.usablePanelFrame(in: visible, showsChat: false), visible)
    }

    func testAuxiliaryBubbleFlipsBelowPetNearTopEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let pet = CGRect(x: 700, y: 500, width: 240, height: 280)
        let bubble = CGSize(width: 350, height: 120)
        let layout = PetLayout.auxiliaryBubbleLayout(
            petVisualFrame: pet,
            bubbleSize: bubble,
            visibleFrame: visible
        )

        XCTAssertEqual(layout.placement, .belowPet)
        XCTAssertEqual(
            layout.origin.y + bubble.height,
            pet.minY + PetLayout.auxiliaryBubbleBelowOverlap,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(layout.origin.x, visible.minX)
        XCTAssertLessThanOrEqual(layout.origin.x + bubble.width, visible.maxX)
    }

    func testAuxiliaryBubbleUsesSmallTopOverlap() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let pet = CGRect(x: 460, y: 160, width: 245, height: 245)
        let bubble = CGSize(width: 350, height: 120)
        let layout = PetLayout.auxiliaryBubbleLayout(
            petVisualFrame: pet,
            bubbleSize: bubble,
            visibleFrame: visible
        )

        XCTAssertEqual(layout.placement, .abovePet)
        XCTAssertEqual(
            layout.origin.y,
            pet.maxY + PetLayout.auxiliaryBubbleAboveGap,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(PetLayout.auxiliaryBubbleAboveGap, 4)
        XCTAssertGreaterThan(layout.origin.y + bubble.height, pet.maxY)
    }

    func testVisiblePetFrameUsesCurrentSpritesOpaqueBounds() {
        let sprite = CGRect(x: 100, y: 200, width: 326, height: 326)
        let normalized = CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.55)
        let visible = PetLayout.visiblePetFrame(
            spriteFrame: sprite,
            normalizedVisibleBounds: normalized
        )
        XCTAssertEqual(visible.minX, 165.2, accuracy: 0.001)
        XCTAssertEqual(visible.minY, 232.6, accuracy: 0.001)
        XCTAssertEqual(visible.width, 195.6, accuracy: 0.001)
        XCTAssertEqual(visible.height, 179.3, accuracy: 0.001)
    }

    func testChatComposerReservesCharacterClearance() {
        XCTAssertGreaterThanOrEqual(PetLayout.chatPetBottomInset, 100)
        let panel = CGRect(x: 20, y: 30, width: 450, height: 506.5)
        let visual = PetLayout.petVisualFrame(panelFrame: panel, scale: 0.75, showsChat: true)
        XCTAssertEqual(visual.minY - panel.minY, PetLayout.chatPetBottomInset, accuracy: 0.001)
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

    func testMaintenanceBubbleUsesCompactQuickSurface() {
        let normal = PetLayout.panelSize(scale: PetLayout.defaultScale, showsBubble: false)
        let maintenance = PetLayout.panelSize(
            scale: PetLayout.defaultScale,
            showsBubble: false,
            showsMaintenance: true
        )
        XCTAssertGreaterThanOrEqual(maintenance.width, PetLayout.minimumMaintenanceWidth)
        XCTAssertEqual(maintenance.height - normal.height, PetLayout.maintenanceHeight)
        XCTAssertLessThan(PetLayout.maintenanceHeight, 340)

        let quickBubble = PetLayout.auxiliaryBubblePanelSize(
            scale: PetLayout.defaultScale,
            showsMaintenance: true
        )
        XCTAssertEqual(quickBubble.width, PetLayout.minimumMaintenanceWidth)
        XCTAssertEqual(quickBubble.height, PetLayout.maintenanceHeight + 18)

        let scanningBubble = PetLayout.auxiliaryBubblePanelSize(
            scale: PetLayout.defaultScale,
            showsMaintenance: true,
            maintenanceIsBusy: true
        )
        XCTAssertEqual(scanningBubble.height, PetLayout.maintenanceScanningHeight + 18)
        XCTAssertLessThan(scanningBubble.height, quickBubble.height)

        let completionBubble = PetLayout.auxiliaryBubblePanelSize(
            scale: PetLayout.defaultScale,
            showsMaintenance: true,
            maintenanceIsCompleted: true
        )
        XCTAssertEqual(completionBubble.height, PetLayout.maintenanceCompletionHeight + 18)
        XCTAssertLessThan(completionBubble.height, quickBubble.height)
    }

    func testMaintenanceResizeClampsAndRestoresCompactOriginAtDisplayEdges() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let scale = PetLayout.defaultScale
        let compactSize = PetLayout.panelSize(scale: scale, showsBubble: false)
        let maintenanceSize = PetLayout.panelSize(
            scale: scale,
            showsBubble: false,
            showsMaintenance: true
        )
        let usable = PetLayout.usablePanelFrame(
            in: visible,
            showsChat: false,
            showsMaintenance: true
        )
        let originalOrigins = [
            CGPoint(x: visible.minX - 60, y: 120),
            CGPoint(x: visible.maxX - compactSize.width + 60, y: 120)
        ]

        for originalOrigin in originalOrigins {
            let expanded = PetLayout.resizedPanelFrame(
                from: CGRect(origin: originalOrigin, size: compactSize),
                targetSize: maintenanceSize,
                scale: scale,
                oldShowsChat: false,
                newShowsChat: false,
                newShowsMaintenance: true,
                visibleFrame: usable
            )
            XCTAssertGreaterThanOrEqual(expanded.minX, usable.minX)
            XCTAssertLessThanOrEqual(expanded.maxX, usable.maxX)
            XCTAssertGreaterThanOrEqual(expanded.minY, usable.minY)
            XCTAssertLessThanOrEqual(expanded.maxY, usable.maxY)

            let restored = PetLayout.restoredCompactOrigin(
                originalOrigin,
                panelSize: compactSize,
                scale: scale,
                visibleFrame: visible
            )
            XCTAssertEqual(restored.x, originalOrigin.x, accuracy: 0.001)
            XCTAssertEqual(restored.y, originalOrigin.y, accuracy: 0.001)
        }
    }

    func testEdgeDockingDetectsEveryScreenSideAndIgnoresCenter() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = CGSize(width: 326, height: 326)

        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: -170, y: 200), size: size), in: visible), .left)
        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: 1_280, y: 200), size: size), in: visible), .right)
        XCTAssertEqual(
            PetLayout.dockingEdge(
                for: CGRect(origin: CGPoint(x: 400, y: 740), size: size),
                in: visible,
                allowedEdges: Set(PetDockEdge.allCases)
            ),
            .top
        )
        XCTAssertEqual(
            PetLayout.dockingEdge(
                for: CGRect(origin: CGPoint(x: 400, y: -170), size: size),
                in: visible,
                allowedEdges: Set(PetDockEdge.allCases)
            ),
            .bottom
        )
        XCTAssertNil(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: 400, y: 250), size: size), in: visible))
        XCTAssertEqual(PetLayout.dockingEdge(for: CGRect(origin: CGPoint(x: -150, y: 250), size: size), in: visible), .left)
    }

    func testDockingCandidateUsesTwoThresholds() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let nearPreview = CGRect(x: 48, y: 260, width: 240, height: 240)
        let preview = PetLayout.dockingCandidate(for: nearPreview, in: visible)
        XCTAssertEqual(preview?.edge, .left)
        XCTAssertEqual(preview?.distance ?? -1, 48, accuracy: 0.001)
        XCTAssertFalse(preview?.isCommitReady == true)

        let nearCommit = nearPreview.offsetBy(dx: -28, dy: 0)
        let commit = PetLayout.dockingCandidate(for: nearCommit, in: visible)
        XCTAssertEqual(commit?.edge, .left)
        XCTAssertEqual(commit?.distance ?? -1, 20, accuracy: 0.001)
        XCTAssertTrue(commit?.isCommitReady == true)

        let awayFromEdge = nearPreview.offsetBy(dx: 20, dy: 0)
        XCTAssertNil(PetLayout.dockingCandidate(for: awayFromEdge, in: visible))
    }

    func testDefaultDockEdgesOnlyIncludeLeftAndRight() {
        XCTAssertEqual(PetLayout.defaultDockEdges, [.left, .right])
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let nearTop = CGRect(x: 500, y: 606, width: 240, height: 240)
        XCTAssertNil(PetLayout.dockingCandidate(for: nearTop, in: visible))
        XCTAssertEqual(
            PetLayout.dockingCandidate(
                for: nearTop,
                in: visible,
                allowedEdges: Set(PetDockEdge.allCases)
            )?.edge,
            .top
        )
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

        for edge in PetLayout.defaultDockEdges {
            let peek = PetLayout.edgePeekOrigin(edge: edge, anchorFrame: anchor, visibleFrame: visible)
            let peekFrame = CGRect(origin: peek, size: PetLayout.edgePeekSize)
            XCTAssertEqual(peekFrame.intersection(visible).width, PetLayout.edgePeekExposedWidth, accuracy: 0.001)

            let hoveredPeek = PetLayout.edgePeekOrigin(
                edge: edge,
                anchorFrame: anchor,
                visibleFrame: visible,
                exposedWidth: PetLayout.edgePeekHoverExposedWidth
            )
            let hoveredFrame = CGRect(origin: hoveredPeek, size: PetLayout.edgePeekSize)
            XCTAssertEqual(
                hoveredFrame.intersection(visible).width,
                PetLayout.edgePeekHoverExposedWidth,
                accuracy: 0.001
            )

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

    func testTuckedPetStartsWithOnlyItsEdgeStripVisible() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let panelOrigin = CGPoint(x: 300, y: 260)
        let petFrame = CGRect(x: 420, y: 280, width: 240, height: 220)

        for edge in PetLayout.defaultDockEdges {
            let tucked = PetLayout.tuckedOrigin(
                edge: edge,
                panelOrigin: panelOrigin,
                visiblePetFrame: petFrame,
                visibleFrame: visible
            )
            let movedPet = petFrame.offsetBy(
                dx: tucked.x - panelOrigin.x,
                dy: tucked.y - panelOrigin.y
            )
            XCTAssertEqual(
                movedPet.intersection(visible).width,
                PetLayout.edgePeekExposedWidth,
                accuracy: 0.001
            )
        }
    }

    func testEdgePeekUsesCompactPointerFootprint() {
        XCTAssertLessThanOrEqual(PetLayout.edgePeekSize.width, 72)
        XCTAssertLessThanOrEqual(PetLayout.edgePeekSize.height, 84)
        XCTAssertEqual(PetLayout.edgePeekExposedWidth, 38)
        XCTAssertEqual(PetLayout.edgePeekHoverExposedWidth, 60)
        XCTAssertLessThanOrEqual(PetLayout.edgeStatusSize.width, 70)
    }

    func testRestoredPetArtworkIsMovedFullyInsideVisibleScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let panelOrigin = CGPoint(x: 1_020, y: 200)
        let petFrame = CGRect(x: 1_330, y: 240, width: 180, height: 260)
        let restored = PetLayout.originEnsuringContentVisible(
            panelOrigin: panelOrigin,
            contentFrame: petFrame,
            visibleFrame: visible,
            inset: PetLayout.restoredPetScreenInset
        )
        let movedPet = petFrame.offsetBy(
            dx: restored.x - panelOrigin.x,
            dy: restored.y - panelOrigin.y
        )

        XCTAssertGreaterThanOrEqual(movedPet.minX, visible.minX + PetLayout.restoredPetScreenInset)
        XCTAssertLessThanOrEqual(movedPet.maxX, visible.maxX - PetLayout.restoredPetScreenInset)
        XCTAssertGreaterThanOrEqual(movedPet.minY, visible.minY + PetLayout.restoredPetScreenInset)
        XCTAssertLessThanOrEqual(movedPet.maxY, visible.maxY - PetLayout.restoredPetScreenInset)
    }

    func testRestoredExpandedPanelUsesOnlyBoundedHorizontalOverflow() {
        let visible = CGRect(x: 0, y: 76, width: 1_470, height: 847)
        let panelSize = CGSize(width: 270, height: 195)
        let staleCompactOrigin = CGPoint(x: 1_254, y: 756)
        let restored = PetLayout.constrainedOrigin(
            staleCompactOrigin,
            panelSize: panelSize,
            visibleFrame: visible,
            allowedTopOverflow: 29,
            allowedRightOverflow: PetLayout.restoredPanelHorizontalOverflow
        )

        XCTAssertEqual(
            restored.x,
            visible.maxX - panelSize.width + PetLayout.restoredPanelHorizontalOverflow
        )
        XCTAssertLessThanOrEqual(
            restored.x + panelSize.width,
            visible.maxX + PetLayout.restoredPanelHorizontalOverflow
        )
    }

    func testUrgentEdgeMessagesUseDistinctCharacterVoices() {
        for state in [SmartPetState.lowBattery, .memoryPressure] {
            let messages = PetMode.allCases.map {
                PetEdgeMessageResolver.alert(
                    for: $0,
                    state: state,
                    snapshot: .empty
                )
            }
            XCTAssertEqual(Set(messages).count, PetMode.allCases.count)
            XCTAssertTrue(messages.allSatisfy { !$0.contains("点我") })
        }
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

    func testBatteryAlertLevelsUseWarningAtTwentyAndCriticalAtTenPercent() {
        func battery(_ fraction: Double, charging: Bool = false) -> BatteryMetrics {
            BatteryMetrics(
                isPresent: true,
                chargeFraction: fraction,
                isCharging: charging,
                powerSource: charging ? .ac : .battery,
                timeRemainingMinutes: nil
            )
        }

        XCTAssertEqual(BatteryAlertLevel.resolve(from: battery(0.21)), .normal)
        XCTAssertEqual(BatteryAlertLevel.resolve(from: battery(0.20)), .warning)
        XCTAssertEqual(BatteryAlertLevel.resolve(from: battery(0.11)), .warning)
        XCTAssertEqual(BatteryAlertLevel.resolve(from: battery(0.10)), .critical)
        XCTAssertEqual(BatteryAlertLevel.resolve(from: battery(0.05)), .critical)
        XCTAssertEqual(BatteryAlertLevel.resolve(from: battery(0.05, charging: true)), .normal)
    }

    func testBatteryWarningIsTransientAndCriticalBatteryIsUrgent() {
        let suite = "PetStoreBatteryReminderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )

        store.applySmartStates([.lowBattery], batteryAlertLevel: .warning)
        XCTAssertFalse(store.urgentReminderVisible)
        XCTAssertFalse(store.shouldShowPetBubble)
        XCTAssertEqual(PetStore.batteryWarningReminderIntervalSeconds, 300)

        store.applySmartStates([.lowBattery], batteryAlertLevel: .critical)
        XCTAssertTrue(store.urgentReminderVisible)
        XCTAssertTrue(store.shouldShowPetBubble)

        store.setUrgentReminderMode(.interval)
        XCTAssertTrue(
            store.urgentReminderVisible,
            "10% 及以下的电量提醒应始终常驻，不受间隔提醒模式影响"
        )
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
        XCTAssertFalse(PetStatusMessageResolver.message(snapshot: snapshot, smartState: .normal).isEmpty)

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
        XCTAssertFalse(cpuMessage.isEmpty)
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
            isSmartStateUrgent: false,
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
            isSmartStateUrgent: false,
            transientSmartState: .rainy
        ))

        XCTAssertEqual(listening, mode.musicAction)
        XCTAssertEqual(transientRain, mode.smartAction(for: .rainy))
    }

    func testStandaloneMusicNoteHidesWhileLyricBubbleIsVisible() {
        let showsLyricBubble = PetMusicPresentationPolicy.showsLyricBubble(
            isPlaying: true,
            lightSingAlongEnabled: true,
            hasCurrentLyric: true,
            isChatPresented: false,
            hasMaintenanceTask: false,
            focusState: .idle
        )

        XCTAssertTrue(showsLyricBubble)
        XCTAssertFalse(
            PetMusicPresentationPolicy.showsStandaloneMusicIndicator(
                isPlaying: true,
                showsLyricBubble: showsLyricBubble
            )
        )
        XCTAssertTrue(
            PetMusicPresentationPolicy.showsStandaloneMusicIndicator(
                isPlaying: true,
                showsLyricBubble: false
            )
        )
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
            isSmartStateUrgent: true,
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

        XCTAssertTrue(messages.contains { $0.contains("°") })
        XCTAssertFalse(messages.isEmpty)
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
            XCTAssertFalse(messages.isEmpty)
        }
        let vcc = PetAmbientChatter.candidates(
            mode: .vcc,
            system: snapshot,
            weather: nil,
            locationName: "上海市"
        )
        XCTAssertFalse(vcc.isEmpty)
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
        XCTAssertFalse(rain.isEmpty)
        XCTAssertTrue(rain.contains { $0.contains("杭州市") })

        let hot = PetAmbientChatter.weatherAnnouncements(
            mode: .vcc,
            weather: weather(temperature: 32, apparent: 36, code: 1)
        )
        XCTAssertFalse(hot.isEmpty)

        let cold = PetAmbientChatter.weatherAnnouncements(
            mode: .yuanGui,
            weather: weather(temperature: 6, apparent: 4, code: 2)
        )
        XCTAssertFalse(cold.isEmpty)
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
