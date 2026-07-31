import XCTest
@testable import YuanGUI

private struct TestError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private actor StubUpdateChecker: UpdateChecking {
    let result: Result<UpdateCheckResult, TestError>
    private(set) var callCount = 0

    init(result: Result<UpdateCheckResult, TestError>) {
        self.result = result
    }

    func checkForUpdate() async throws -> UpdateCheckResult {
        callCount += 1
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

private final class MutableDateProvider {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private final class Counter {
    var count = 0
}

private final class LogCollector {
    private(set) var messages: [String] = []
    func append(_ message: String) { messages.append(message) }
}

@MainActor
private final class FakeUpdatePromptEnvironment: UpdatePromptEnvironment {
    var isApplicationActive = true
    var hasBlockingModalPresentation = false
}

@MainActor
private final class FakeUpdatePromptPresenter: UpdatePromptPresenting {
    private(set) var isPresenting = false
    private(set) var presentCount = 0
    private(set) var lastRelease: GitHubRelease?
    private(set) var lastHighlights: [String] = []
    private var installAction: (() -> Void)?
    private var laterAction: (() -> Void)?
    private var detailsAction: (() -> Void)?

    func presentUpdate(
        currentVersion: String,
        release: GitHubRelease,
        highlights: [String],
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onShowDetails: @escaping () -> Void
    ) {
        guard !isPresenting else { return }
        presentCount += 1
        isPresenting = true
        lastRelease = release
        lastHighlights = highlights
        installAction = onInstall
        laterAction = onLater
        detailsAction = onShowDetails
    }

    func dismiss() {
        dismiss(choosingInstall: false)
    }

    func dismiss(choosingInstall: Bool) {
        guard isPresenting else { return }
        isPresenting = false
        if choosingInstall {
            installAction?()
        } else {
            laterAction?()
        }
    }

    func chooseDetails() {
        guard isPresenting else { return }
        isPresenting = false
        detailsAction?()
    }
}

@MainActor
private struct Fixture {
    let coordinator: AutomaticUpdateCheckCoordinator
    let store: AppUpdateStore
    let presenter: FakeUpdatePromptPresenter
    let checker: StubUpdateChecker
    let defaults: UserDefaults
    let provider: MutableDateProvider
    let installCount: Counter
    let detailsCount: Counter
    let logs: LogCollector
    let environment: FakeUpdatePromptEnvironment
    let suite: String

    static func make(
        result: Result<UpdateCheckResult, TestError>,
        store: AppUpdateStore? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        startupDelay: Duration = .zero
    ) -> Fixture {
        let suite = "AutomaticUpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let checker = StubUpdateChecker(result: result)
        let store = store ?? AppUpdateStore()
        let presenter = FakeUpdatePromptPresenter()
        let environment = FakeUpdatePromptEnvironment()
        let provider = MutableDateProvider(now)
        let installCount = Counter()
        let detailsCount = Counter()
        let logs = LogCollector()
        let coordinator = AutomaticUpdateCheckCoordinator(
            checker: checker,
            store: store,
            presenter: presenter,
            environment: environment,
            defaults: defaults,
            calendar: calendar,
            now: { provider.now },
            startupDelay: startupDelay,
            install: { installCount.count += 1 },
            showDetails: { detailsCount.count += 1 },
            log: { logs.append($0) }
        )
        return Fixture(
            coordinator: coordinator,
            store: store,
            presenter: presenter,
            checker: checker,
            defaults: defaults,
            provider: provider,
            installCount: installCount,
            detailsCount: detailsCount,
            logs: logs,
            environment: environment,
            suite: suite
        )
    }

    func cleanup() {
        coordinator.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private func makeRelease(_ version: String, body: String? = nil) -> GitHubRelease {
    GitHubRelease(
        tagName: "v\(version)",
        name: "YuanGUI \(version)",
        body: body ?? "Release notes for \(version)",
        pageURL: URL(string: "https://github.com/YangChen-cn/yuangui/releases/tag/v\(version)")!,
        assets: []
    )
}

@MainActor
private func makeDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int, _ minute: Int, _ second: Int,
    calendar: Calendar
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
}

@MainActor
private func waitUntil(
    _ condition: @escaping () -> Bool,
    timeout: TimeInterval = 2
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@MainActor
private func waitForCallCount(
    _ checker: StubUpdateChecker,
    _ expected: Int,
    timeout: TimeInterval = 2
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if await checker.callCount >= expected { return true }
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
final class AutomaticUpdateTests: XCTestCase {

    // MARK: - Daily limit

    func testFirstAutomaticTriggerChecksAndPromptsForAvailable() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "notes")))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertEqual(fixture.store.state, .available)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.check.started"))
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.prompt.presented"))
    }

    func testSecondAutomaticTriggerSameDayIsSkipped() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.coordinator.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.alreadyChecked"))
    }

    func testRecreatedCoordinatorSameDayDoesNotCheckAgain() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        // A brand new coordinator sharing the same defaults must respect the
        // persisted "checked today" marker.
        let secondChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let secondPresenter = FakeUpdatePromptPresenter()
        let second = AutomaticUpdateCheckCoordinator(
            checker: secondChecker,
            store: AppUpdateStore(),
            presenter: secondPresenter,
            defaults: fixture.defaults,
            calendar: .autoupdatingCurrent,
            now: { fixture.provider.now }
        )
        second.runAutomaticCheckIfNeeded()

        let firstCalls = await fixture.checker.callCount
        let secondCalls = await secondChecker.callCount
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 0)
        XCTAssertEqual(secondPresenter.presentCount, 0)
    }

    func testNextNaturalDayChecksAgain() async {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            now: makeDate(2026, 8, 1, 23, 59, 0, calendar: utc),
            calendar: utc
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        fixture.provider.now = makeDate(2026, 8, 2, 0, 1, 0, calendar: utc)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)
    }

    func testTimeZoneDayBoundaryIsHandledByCalendar() async {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            now: makeDate(2026, 8, 1, 23, 59, 0, calendar: utc),
            calendar: utc
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        // The marker is persisted as start-of-day; comparing in a second,
        // different calendar must not crash or get permanently stuck. Here the
        // wall-clock day has not changed, so the automatic check stays quiet.
        var pacific = calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let pacificNow = makeDate(2026, 8, 1, 16, 0, 0, calendar: utc)
        let recreated = AutomaticUpdateCheckCoordinator(
            checker: StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1")))),
            store: AppUpdateStore(),
            presenter: FakeUpdatePromptPresenter(),
            defaults: fixture.defaults,
            calendar: pacific,
            now: { pacificNow }
        )
        recreated.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
    }

    func testConcurrentTriggersProduceOnlyOneRequest() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        fixture.coordinator.runAutomaticCheckIfNeeded()
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
    }

    // MARK: - Manual checks

    func testManualCheckIsNotBlockedByDailyLimit() async {
        // A manual check on the shared store must run even though the
        // automatic coordinator already marked today as checked.
        let storeChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let store = AppUpdateStore(checking: storeChecker)
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            store: store
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        store.check()
        _ = await waitUntil { store.state == .upToDate }

        let manualCalls = await storeChecker.callCount
        XCTAssertEqual(manualCalls, 1)
        XCTAssertEqual(store.state, .upToDate)
    }

    func testSuccessfulManualCheckSuppressesSameDayAutomaticCheck() async {
        let storeChecker = StubUpdateChecker(result: .success(.upToDate(makeRelease("2.7.1"))))
        let store = AppUpdateStore(checking: storeChecker)
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("99.9.9"))),
            store: store
        )
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        store.check()
        _ = await waitUntil { store.state == .upToDate }

        // The manual success marked the day; a follow-up automatic trigger
        // must not hit the network again.
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.alreadyChecked"))
    }

    func testManualCheckErrorStillShowsFailure() async {
        let storeChecker = StubUpdateChecker(result: .failure(TestError(message: "boom")))
        let store = AppUpdateStore(checking: storeChecker)
        store.check()
        _ = await waitUntil {
            if case .failed = store.state { return true }
            return false
        }
        if case .failed(let message) = store.state {
            XCTAssertEqual(message, "boom")
        } else {
            XCTFail("Manual check error should leave the store in failed state")
        }
        XCTAssertNil(store.latestRelease)
    }

    // MARK: - Prompt behavior

    func testNoPromptWhenUpToDate() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        XCTAssertEqual(fixture.store.state, .idle)
    }

    func testNoPromptWhenLatestIsOlderThanCurrent() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("1.0.0"))))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.check.upToDate"))
    }

    func testAvailableUpdatePromptsExactlyOnce() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertEqual(fixture.store.state, .available)
    }

    func testNoSecondPromptWhileOneIsPresented() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        XCTAssertTrue(fixture.presenter.isPresenting)

        // A new natural day arrives while the user still has the alert open.
        fixture.provider.now = fixture.provider.now.addingTimeInterval(86_400)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.promptPresented"))
    }

    func testPromptPresenterIgnoresSecondPresentation() async {
        let presenter = FakeUpdatePromptPresenter()
        presenter.presentUpdate(
            currentVersion: "2.7.1",
            release: makeRelease("99.9.9"),
            highlights: [],
            onInstall: {},
            onLater: {},
            onShowDetails: {}
        )
        presenter.presentUpdate(
            currentVersion: "2.7.1",
            release: makeRelease("99.9.9"),
            highlights: [],
            onInstall: {},
            onLater: {},
            onShowDetails: {}
        )
        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertTrue(presenter.isPresenting)
    }

    func testLaterDoesNotStartInstall() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        fixture.presenter.dismiss(choosingInstall: false)

        XCTAssertEqual(fixture.installCount.count, 0)
        XCTAssertEqual(fixture.store.state, .available)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.prompt.later"))
        XCTAssertFalse(fixture.logs.messages.contains("update.auto.prompt.install"))
    }

    func testInstallActionRunsExactlyOnce() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        fixture.presenter.dismiss(choosingInstall: true)
        // Simulate a rapid second activation of the primary action.
        fixture.presenter.dismiss(choosingInstall: true)

        XCTAssertEqual(fixture.installCount.count, 1)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.prompt.install"))
    }

    func testLaterSuppressesSameDayAutomaticPrompt() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.presenter.dismiss(choosingInstall: false)

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.presenter.presentCount, 1)
    }

    func testSameAvailableVersionRemindsAgainNextDay() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.presenter.dismiss(choosingInstall: false)

        fixture.provider.now = fixture.provider.now.addingTimeInterval(86_400)
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(fixture.presenter.presentCount, 2)
    }

    // MARK: - Failure and lifecycle

    func testAutomaticNetworkFailureStaysQuiet() async {
        let fixture = Fixture.make(result: .failure(TestError(message: "offline")))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        XCTAssertEqual(fixture.store.state, .idle)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.check.failed"))
    }

    func testAutomaticCheckSkippedWhileStoreIsBusy() async {
        let store = AppUpdateStore()
        store.commitAutomaticUpdate(release: makeRelease("99.9.9"), notes: nil)
        store.installLauncher = { _ in }
        store.installLatest() // moves state to .downloading synchronously

        let fixture = Fixture.make(
            result: .success(.available(makeRelease("99.9.9"), notes: nil)),
            store: store
        )
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(fixture.logs.messages.contains("update.auto.skipped.busy"))
        _ = await waitUntil { store.state == .installing }
    }

    func testStopPreventsFurtherChecksAndRemovesObserver() async {
        let fixture = Fixture.make(result: .success(.upToDate(makeRelease("2.7.1"))))
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        _ = await waitForCallCount(fixture.checker, 1)

        fixture.coordinator.stop()
        // Reset the daily marker so only the observer removal / stopped flag
        // can explain why nothing else fires.
        fixture.defaults.removeObject(forKey: AutomaticUpdateCheckCoordinator.lastAutomaticCheckDayKey)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 1)
    }

    func testRunAfterStopIsANoOp() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: nil)))
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        fixture.coordinator.stop()
        fixture.coordinator.runAutomaticCheckIfNeeded()

        let calls = await fixture.checker.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(fixture.presenter.presentCount, 0)
    }

    // MARK: - Presentation timing and pending state

    func testStartupActivationDoesNotBypassDelayAndChecksOnceAfterwards() async {
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            startupDelay: .milliseconds(120)
        )
        defer { fixture.cleanup() }

        fixture.coordinator.start()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        let earlyCallCount = await fixture.checker.callCount
        XCTAssertEqual(earlyCallCount, 0)

        let didCheck = await waitForCallCount(fixture.checker, 1, timeout: 1)
        XCTAssertTrue(didCheck)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        let finalCallCount = await fixture.checker.callCount
        XCTAssertEqual(finalCallCount, 1)
    }

    func testInactiveApplicationKeepsUpdatePendingUntilNextActivation() async {
        let fixture = Fixture.make(
            result: .success(.available(makeRelease("99.9.9"), notes: "- Faster launch")),
            startupDelay: .zero
        )
        defer { fixture.cleanup() }

        fixture.environment.isApplicationActive = false
        fixture.coordinator.start()
        try? await Task.sleep(for: .milliseconds(20))
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
        fixture.environment.isApplicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        let didPresent = await waitUntil { fixture.presenter.presentCount == 1 }
        XCTAssertTrue(didPresent)
    }

    func testBlockingModalDefersPromptUntilSheetEnds() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "- Safer updates")))
        defer { fixture.cleanup() }

        fixture.environment.hasBlockingModalPresentation = true
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        XCTAssertEqual(fixture.presenter.presentCount, 0)

        fixture.environment.hasBlockingModalPresentation = false
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: nil)
        fixture.coordinator.tryPresentPendingUpdate()
        XCTAssertEqual(fixture.presenter.presentCount, 1)
    }

    func testStopDiscardsPendingUpdate() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "- Deferred")))
        defer { fixture.cleanup() }

        fixture.environment.isApplicationActive = false
        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.coordinator.stop()
        fixture.environment.isApplicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(fixture.presenter.presentCount, 0)
    }

    func testManualAvailableResultDoesNotOpenAutomaticPrompt() async {
        let checker = StubUpdateChecker(
            result: .success(.available(makeRelease("99.9.9"), notes: "- Manual result"))
        )
        let store = AppUpdateStore(checking: checker)
        let fixture = Fixture.make(
            result: .success(.upToDate(makeRelease("2.7.1"))),
            store: store
        )
        defer { fixture.cleanup() }

        store.check()
        let becameAvailable = await waitUntil { store.state == .available }
        XCTAssertTrue(becameAvailable)
        XCTAssertEqual(fixture.presenter.presentCount, 0)
    }

    func testDetailsActionKeepsAvailableStoreStateAndRunsOnce() async {
        let fixture = Fixture.make(result: .success(.available(makeRelease("99.9.9"), notes: "- Details")))
        defer { fixture.cleanup() }

        fixture.coordinator.runAutomaticCheckIfNeeded()
        await fixture.coordinator.awaitCurrentCheck()
        fixture.presenter.chooseDetails()
        fixture.presenter.chooseDetails()

        XCTAssertEqual(fixture.detailsCount.count, 1)
        XCTAssertEqual(fixture.store.state, .available)
    }

    // MARK: - Prompt content and geometry

    func testHighlightsPreferBulletsAndSkipReleaseHeading() {
        let release = makeRelease(
            "2.7.2",
            body: "## YuanGUI 2.7.2\n\n- **Faster** dashboard refresh\n- Added `View Details` action\n- This third item is not shown"
        )

        XCTAssertEqual(
            AutomaticUpdateCheckCoordinator.highlights(for: release, notes: nil),
            ["Faster dashboard refresh", "Added View Details action"]
        )
    }

    func testHighlightsReturnEmptyForEmptyOrHeadingOnlyNotes() {
        XCTAssertEqual(
            AutomaticUpdateCheckCoordinator.highlights(for: makeRelease("2.7.2", body: ""), notes: nil),
            []
        )
        XCTAssertEqual(
            AutomaticUpdateCheckCoordinator.highlights(for: makeRelease("2.7.2", body: "# 2.7.2"), notes: nil),
            []
        )
    }

    func testPromptPlacementCentersWithinVisibleFrameAndClampsSize() {
        let visibleFrame = CGRect(x: -1280, y: 23, width: 1920, height: 1057)
        let frame = UpdatePromptWindowPlacement.centeredFrame(
            windowSize: CGSize(width: 900, height: 900),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.size, CGSize(width: 500, height: 360))
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testPromptPlacementHandlesVerticalMonitorAndDockOffset() {
        let visibleFrame = CGRect(x: 0, y: 1080, width: 1440, height: 900)
        let origin = UpdatePromptWindowPlacement.centeredOrigin(
            windowSize: CGSize(width: 460, height: 300),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 490, accuracy: 0.001)
        XCTAssertEqual(origin.y, 1380, accuracy: 0.001)
    }

    // MARK: - Store install guard

    func testInstallLatestIgnoresRapidRepeatedClicks() async {
        let store = AppUpdateStore()
        var installCount = 0
        store.installLauncher = { _ in installCount += 1 }
        store.commitAutomaticUpdate(release: makeRelease("99.9.9"), notes: nil)

        store.installLatest()
        store.installLatest() // second click is ignored while the first runs

        _ = await waitUntil { store.state == .installing }
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(store.state, .installing)
    }

    // MARK: - Localization

    func testAutoUpdatePromptKeysExistInBothLanguagesAndFormatInEnglish() {
        let english = AppLocalizer.localizedValues(for: "en")
        let chinese = AppLocalizer.localizedValues(for: "zh-Hans")
        let keys = [
            "update.auto.window.title",
            "update.auto.prompt.title",
            "update.auto.prompt.versionTransition",
            "update.auto.prompt.highlights",
            "update.auto.prompt.safeInstall",
            "update.auto.prompt.install",
            "update.auto.prompt.later",
            "update.auto.prompt.details"
        ]
        for key in keys {
            XCTAssertNotNil(english[key], "Missing English key: \(key)")
            XCTAssertNotNil(chinese[key], "Missing Simplified Chinese key: \(key)")
        }
        XCTAssertEqual(
            String(format: tryUnwrap(english["update.auto.prompt.versionTransition"]), "2.7.0", "2.7.1"),
            "2.7.0 → 2.7.1"
        )
        XCTAssertEqual(english["update.auto.prompt.install"], "Update Now")
        XCTAssertEqual(english["update.auto.prompt.later"], "Later")
        XCTAssertEqual(english["update.auto.prompt.details"], "View Details")
    }

    private func tryUnwrap(_ value: String?) -> String {
        guard let value else {
            XCTFail("Required localization value is missing")
            return ""
        }
        return value
    }
}
