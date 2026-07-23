import Foundation
import XCTest
@testable import YuanGUI

@MainActor
final class ExternalAudioInterruptionTests: XCTestCase {
    func testSettingsDefaultToDisabledWithAutomaticResumeAvailable() {
        let suiteName = "ExternalAudioDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ExternalAudioInterruptionController(
            playback: RecordingExternalPlayback(isPlaying: true),
            monitor: RecordingExternalMonitor(),
            defaults: defaults,
            sourceProvider: { .bilibili }
        )

        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.resumesAfterExternalAudio)
    }

    func testSustainedExternalAudioAutomaticallyPausesThenResumes() {
        let fixture = makeFixture()
        let start = Date(timeIntervalSinceReferenceDate: 10)

        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(0.99))
        XCTAssertEqual(fixture.playback.pauseCount, 0)

        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(1))
        XCTAssertEqual(fixture.playback.pauseCount, 1)
        XCTAssertFalse(fixture.playback.isPlaying)

        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(2))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(4.49))
        XCTAssertEqual(fixture.playback.resumeCount, 0)

        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(4.5))
        XCTAssertEqual(fixture.playback.resumeCount, 1)
        XCTAssertTrue(fixture.playback.isPlaying)
    }

    func testInitiallyManuallyPausedMusicNeverResumes() {
        let fixture = makeFixture(isPlaying: false)
        let start = Date(timeIntervalSinceReferenceDate: 20)

        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(1))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(2))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(4.5))

        XCTAssertEqual(fixture.playback.pauseCount, 0)
        XCTAssertEqual(fixture.playback.resumeCount, 0)
    }

    func testManualPlaybackOperationCancelsPendingAutomaticResume() {
        let fixture = makeFixture()
        let start = Date(timeIntervalSinceReferenceDate: 30)

        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(1))
        fixture.playback.performManualSourceSwitch()
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(2))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(4.5))

        XCTAssertEqual(fixture.playback.resumeCount, 0)
    }

    func testManualPlaybackDuringExistingExternalAudioOverridesOnlyCurrentSession() {
        let fixture = makeFixture(isPlaying: false)
        let start = Date(timeIntervalSinceReferenceDate: 35)

        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.playback.performManualPlaybackOperation(plays: true)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(1.5))
        XCTAssertEqual(fixture.playback.pauseCount, 0)
        XCTAssertTrue(fixture.playback.isPlaying)
        XCTAssertTrue(fixture.playback.automaticPlaybackIsBlocked)

        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(2))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(4.5))
        XCTAssertFalse(fixture.playback.automaticPlaybackIsBlocked)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(5))
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(6))
        XCTAssertEqual(fixture.playback.pauseCount, 1)
    }

    func testManualPauseAfterAutomaticPauseNeverResumes() {
        let fixture = makeFixture()
        let start = Date(timeIntervalSinceReferenceDate: 37)
        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(1))
        fixture.playback.performManualPlaybackOperation(plays: false)
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(2))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(4.5))

        XCTAssertFalse(fixture.playback.isPlaying)
        XCTAssertEqual(fixture.playback.resumeCount, 0)
    }

    func testShortNotificationAndBackToBackAppsDoNotResumeEarly() {
        let fixture = makeFixture()
        let start = Date(timeIntervalSinceReferenceDate: 40)

        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(0.8))
        XCTAssertEqual(fixture.playback.pauseCount, 0)

        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(2))
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(3))
        XCTAssertEqual(fixture.playback.pauseCount, 1)
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(3.2))
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(5.6))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(5.8))
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(8.29))
        XCTAssertEqual(fixture.playback.resumeCount, 0)
        fixture.controller.receiveActivity(isActive: false, at: start.addingTimeInterval(8.3))
        XCTAssertEqual(fixture.playback.resumeCount, 1)
    }

    func testAppleMusicIsExcludedOnlyWhileItIsThePlaybackSource() {
        var source: MusicSource? = .appleMusic
        let fixture = makeFixture(sourceProvider: { source })
        fixture.controller.start()
        let musicProcess = ExternalAudioProcess(processID: 123, bundleIdentifier: "com.apple.Music")

        XCTAssertTrue(fixture.monitor.excludes(musicProcess))
        source = .bilibili
        XCTAssertFalse(fixture.monitor.excludes(musicProcess))
        XCTAssertTrue(fixture.monitor.excludes(ExternalAudioProcess(
            processID: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: "com.example.YuanGUI"
        )))
    }

    func testDisablingOrStoppingCleansUpPendingResume() {
        let fixture = makeFixture()
        let start = Date(timeIntervalSinceReferenceDate: 50)
        fixture.controller.receiveActivity(isActive: true, at: start)
        fixture.controller.receiveActivity(isActive: true, at: start.addingTimeInterval(1))

        fixture.controller.setEnabled(false)
        XCTAssertEqual(fixture.playback.cancelCount, 1)
        XCTAssertEqual(fixture.monitor.stopCount, 1)

        fixture.controller.start()
        fixture.controller.stop()
        XCTAssertGreaterThanOrEqual(fixture.monitor.stopCount, 2)
    }

    private func makeFixture(
        isPlaying: Bool = true,
        sourceProvider: @escaping () -> MusicSource? = { .bilibili }
    ) -> (controller: ExternalAudioInterruptionController, playback: RecordingExternalPlayback, monitor: RecordingExternalMonitor) {
        let suiteName = "ExternalAudioInterruptionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: ExternalAudioInterruptionController.enabledDefaultsKey)
        let playback = RecordingExternalPlayback(isPlaying: isPlaying)
        let monitor = RecordingExternalMonitor()
        let controller = ExternalAudioInterruptionController(
            playback: playback,
            monitor: monitor,
            defaults: defaults,
            sourceProvider: sourceProvider
        )
        return (controller, playback, monitor)
    }
}

@MainActor
private final class RecordingExternalPlayback: ExternalAudioPlaybackControlling {
    var onExternalAudioResumeCancelled: (() -> Void)?
    var onExternalAudioManualControl: (() -> Void)?
    var blocksAutomaticPlaybackForExternalAudio: (() -> Bool)?
    var isPlaying: Bool
    private var automaticallyPaused = false
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var cancelCount = 0

    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    func pauseForExternalAudio() {
        guard isPlaying else { return }
        isPlaying = false
        automaticallyPaused = true
        pauseCount += 1
    }

    func resumeAfterExternalAudio() {
        guard automaticallyPaused else { return }
        automaticallyPaused = false
        isPlaying = true
        resumeCount += 1
    }

    func cancelExternalAudioResume() {
        let hadAutomaticPause = automaticallyPaused
        automaticallyPaused = false
        cancelCount += 1
        if hadAutomaticPause { onExternalAudioResumeCancelled?() }
    }

    func performManualSourceSwitch() {
        performManualPlaybackOperation(plays: true)
    }

    func performManualPlaybackOperation(plays: Bool) {
        isPlaying = plays
        cancelExternalAudioResume()
        onExternalAudioManualControl?()
    }

    var automaticPlaybackIsBlocked: Bool {
        blocksAutomaticPlaybackForExternalAudio?() ?? false
    }
}

@MainActor
private final class RecordingExternalMonitor: ExternalAudioActivityMonitoring {
    var onActivityChanged: ((Bool) -> Void)?
    private var exclusion: ((ExternalAudioProcess) -> Bool)?
    private(set) var stopCount = 0

    func start(excluding: @escaping (ExternalAudioProcess) -> Bool) {
        exclusion = excluding
    }

    func stop() {
        exclusion = nil
        stopCount += 1
    }

    func excludes(_ process: ExternalAudioProcess) -> Bool {
        exclusion?(process) ?? false
    }
}
