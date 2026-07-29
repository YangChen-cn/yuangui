import Foundation
import XCTest
@testable import YuanGUI

@MainActor
final class FocusTimerTests: XCTestCase {
    func testDurationChangesAreClampedPersistedAndResetWhenIdle() {
        let suite = "FocusTimerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let timer = FocusTimerStore(
            pet: makePet(defaults: defaults),
            defaults: defaults
        )

        timer.setDurationMinutes(45)
        XCTAssertEqual(timer.durationMinutes, 45)
        XCTAssertEqual(timer.remainingSeconds, 45 * 60)
        XCTAssertEqual(defaults.integer(forKey: "focusDurationMinutes"), 45)

        timer.setDurationMinutes(0)
        XCTAssertEqual(timer.durationMinutes, FocusTimerStore.minimumDurationMinutes)
        XCTAssertEqual(timer.remainingSeconds, FocusTimerStore.minimumDurationMinutes * 60)

        timer.setDurationMinutes(999)
        XCTAssertEqual(timer.durationMinutes, FocusTimerStore.maximumDurationMinutes)
        XCTAssertEqual(timer.remainingSeconds, FocusTimerStore.maximumDurationMinutes * 60)
        XCTAssertEqual(defaults.integer(forKey: "focusDurationMinutes"), FocusTimerStore.maximumDurationMinutes)
    }

    func testSavedDurationIsClampedDuringInitialization() {
        let suite = "FocusTimerInitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(999, forKey: "focusDurationMinutes")

        let timer = FocusTimerStore(
            pet: makePet(defaults: defaults),
            defaults: defaults
        )

        XCTAssertEqual(timer.durationMinutes, FocusTimerStore.maximumDurationMinutes)
        XCTAssertEqual(timer.remainingSeconds, FocusTimerStore.maximumDurationMinutes * 60)
    }

    func testDurationGestureUsesTheDominantSwipeAxisInFiveMinuteSteps() {
        XCTAssertEqual(
            FocusTimerDurationGesture.adjustedDuration(
                startDuration: 25,
                translation: CGSize(width: 24, height: 3)
            ),
            35
        )
        XCTAssertEqual(
            FocusTimerDurationGesture.adjustedDuration(
                startDuration: 45,
                translation: CGSize(width: 2, height: 25)
            ),
            35
        )
    }

    private func makePet(defaults: UserDefaults) -> PetStore {
        PetStore(
            monitor: SystemMonitor(coordinator: MetricsCoordinator(readers: [])),
            trashHandler: FakeTrashHandler(),
            defaults: defaults,
            startServices: false
        )
    }
}
