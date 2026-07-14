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
        store.toggleSystemStatus()
        store.setDashboardStyle(.midnight)
        store.setIdleAnimationEnabled(false)

        XCTAssertEqual(defaults.integer(forKey: "petMode"), PetMode.vcc.rawValue)
        XCTAssertTrue(defaults.bool(forKey: "showsSystemStatus"))
        XCTAssertEqual(defaults.integer(forKey: "dashboardStyle"), DashboardStyle.midnight.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "idleAnimationEnabled"))
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
        XCTAssertEqual(store.petScale, 0.7)
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
}
