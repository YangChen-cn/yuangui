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

        XCTAssertEqual(defaults.integer(forKey: "petMode"), PetMode.vcc.rawValue)
        XCTAssertTrue(defaults.bool(forKey: "showsSystemStatus"))
        XCTAssertEqual(defaults.integer(forKey: "dashboardStyle"), DashboardStyle.midnight.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "idleAnimationEnabled"))
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

    func testBottomToolbarPanelSizeMatchesItsFourButtons() {
        XCTAssertEqual(PetLayout.bottomToolbarPanelSize.width, 155)
        XCTAssertEqual(PetLayout.bottomToolbarPanelSize.height, 70)
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

    func testStatusMessageReflectsLiveSystemPressureEvenInNormalActionState() {
        var snapshot = SystemSnapshot.empty
        snapshot.memory = MemoryMetrics(
            total: 100,
            used: 86,
            free: 14,
            active: 50,
            inactive: 10,
            wired: 20,
            compressed: 6,
            cached: 0,
            swapUsed: 0,
            swapTotal: 0,
            pressure: .warning
        )

        let memoryMessage = PetStatusMessageResolver.message(snapshot: snapshot, smartState: .normal)
        XCTAssertTrue(memoryMessage.contains("内存占用有些高"))
        XCTAssertTrue(memoryMessage.contains("86%"))

        snapshot.memory = nil
        snapshot.cpu = CPUMetrics(total: 0.91, user: 0.65, system: 0.26)
        let cpuMessage = PetStatusMessageResolver.message(snapshot: snapshot, smartState: .normal)
        XCTAssertTrue(cpuMessage.contains("CPU 现在有点忙"))
        XCTAssertTrue(cpuMessage.contains("91%"))
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

        XCTAssertFalse(store.shouldShowPetBubble)
        store.showAmbientMessage("元圭和 VCC 来陪你啦～", duration: 60)
        XCTAssertEqual(store.ambientMessage, "元圭和 VCC 来陪你啦～")
        XCTAssertTrue(store.shouldReservePetBubbleSpace)
        XCTAssertFalse(store.showsSystemStatus)

        store.dismissAmbientMessage()
        XCTAssertNil(store.ambientMessage)
        XCTAssertFalse(store.shouldReservePetBubbleSpace)
    }
}
