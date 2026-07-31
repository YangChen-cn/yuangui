import AppKit
import Combine
import Foundation
import OSLog

enum AutomaticUpdateLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yang.yuangui",
        category: "AutomaticUpdate"
    )

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}

/// The surface that shows the "a new version is available" prompt. Kept as a
/// protocol so tests can observe presentation without opening a real alert.
@MainActor
protocol UpdatePromptPresenting: AnyObject {
    var isPresenting: Bool { get }
    func presentUpdate(
        currentVersion: String,
        release: GitHubRelease,
        summary: String?,
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void
    )
}

/// AppKit `NSAlert` implementation for the automatic update prompt.
///
/// The app is an LSUIElement / accessory app, so there may be no ordinary key
/// window at the moment the prompt appears. A sheet is used when a suitable
/// (non-nonactivating) key/main window exists; otherwise a reliable app-modal
/// alert is used. The app is activated only here, after a newer version has
/// already been confirmed by the caller.
@MainActor
final class AppKitUpdatePromptPresenter: UpdatePromptPresenting {
    private(set) var isPresenting = false
    private var activeAlert: NSAlert?

    func presentUpdate(
        currentVersion: String,
        release: GitHubRelease,
        summary: String?,
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        guard !isPresenting else { return }
        isPresenting = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppLocalizer.format("update.auto.prompt.title", release.version)

        var lines: [String] = [
            AppLocalizer.format("update.auto.prompt.currentVersion", currentVersion),
            AppLocalizer.format("update.auto.prompt.newVersion", release.version)
        ]
        if let summary, !summary.isEmpty {
            lines.append(summary)
        }
        lines.append(AppLocalizer.string("update.auto.prompt.message"))
        alert.informativeText = lines.joined(separator: "\n")

        let installButton = alert.addButton(withTitle: AppLocalizer.string("update.auto.prompt.install"))
        installButton.keyEquivalent = "\r"
        let laterButton = alert.addButton(withTitle: AppLocalizer.string("update.auto.prompt.later"))
        laterButton.keyEquivalent = "\u{1b}"
        activeAlert = alert

        NSApp.activate(ignoringOtherApps: true)

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isPresenting = false
            self.activeAlert = nil
            if response == .alertFirstButtonReturn {
                onInstall()
            } else {
                onLater()
            }
        }

        if let window = suitablePresentationWindow() {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            DispatchQueue.main.async {
                let response = alert.runModal()
                completion(response)
            }
        }
    }

    /// A regular window that can host a sheet. The companion and Dashboard are
    /// nonactivating panels and must not become the host, or the prompt would
    /// steal focus from a panel the user did not intend to be interactive.
    private func suitablePresentationWindow() -> NSWindow? {
        for candidate in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }) {
            if candidate.isVisible, !candidate.styleMask.contains(.nonactivatingPanel) {
                return candidate
            }
        }
        return NSApp.windows.first {
            $0.isVisible && !$0.styleMask.contains(.nonactivatingPanel)
        }
    }
}

/// Coordinates the once-per-natural-day automatic update check and prompt.
///
/// The coordinator owns the *automatic* flow only: daily frequency, task
/// lifecycle, concurrency guards, prompt decision, and persistence. Manual
/// checks keep going through `AppUpdateStore.check()`, which is never blocked
/// by the daily limit.
@MainActor
final class AutomaticUpdateCheckCoordinator {
    /// Persisted key for the last natural day an automatic check was attempted.
    static let lastAutomaticCheckDayKey = "updates.lastAutomaticCheckDay"

    /// Delay before the launch-time check, so the companion, menu bar item,
    /// weather, and window setup get out of the way first.
    static let startupDelayNanoseconds: UInt64 = 2_500_000_000

    private let checker: UpdateChecking
    private let store: AppUpdateStore
    private let presenter: UpdatePromptPresenting
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let installAction: () -> Void
    private let log: (String) -> Void

    private var observer: NSObjectProtocol?
    private var startupTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var stateCancellable: AnyCancellable?
    private var isChecking = false
    private var isStopped = false
    private var installTriggered = false

    init(
        checker: UpdateChecking = AppUpdateService(),
        store: AppUpdateStore,
        presenter: UpdatePromptPresenting? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        install: (() -> Void)? = nil,
        log: @escaping (String) -> Void = AutomaticUpdateLog.log
    ) {
        self.checker = checker
        self.store = store
        self.presenter = presenter ?? AppKitUpdatePromptPresenter()
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.installAction = install ?? { [weak store] in store?.installLatest() }
        self.log = log
    }

    /// Installs the single activation observer and schedules the launch-time
    /// check. Safe to call once; repeated calls are ignored.
    func start() {
        guard !isStopped, observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applicationDidBecomeActive()
            }
        }

        // A successful manual check also counts as "checked today", so an
        // automatic request is not fired right after the user checked by hand.
        stateCancellable = store.$state
            .sink { [weak self] state in
                guard state == .available || state == .upToDate else { return }
                Task { @MainActor [weak self] in
                    self?.noteCheckCompleted()
                }
            }

        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            self.runAutomaticCheckIfNeeded(trigger: .automatic)
        }
    }

    /// Cancels the pending launch check and any in-flight check, and removes
    /// the activation observer. No prompt is presented after this is called.
    func stop() {
        isStopped = true
        startupTask?.cancel()
        startupTask = nil
        checkTask?.cancel()
        checkTask = nil
        stateCancellable?.cancel()
        stateCancellable = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    /// The single entry point for an automatic check. Callable directly for
    /// tests; in production it is reached by the launch delay and by the
    /// didBecomeActive observer.
    func runAutomaticCheckIfNeeded(trigger: UpdateCheckTrigger = .automatic) {
        guard !isStopped, !isChecking else { return }
        guard !store.isBusy else {
            log("update.auto.skipped.busy")
            return
        }
        guard !presenter.isPresenting else {
            log("update.auto.skipped.promptPresented")
            return
        }
        guard !hasCheckedToday else {
            log("update.auto.skipped.alreadyChecked")
            return
        }
        markCheckedToday()
        isChecking = true
        log("update.auto.check.started")
        checkTask = Task { [weak self] in
            await self?.performAutomaticCheck(trigger: trigger)
        }
    }

    private func applicationDidBecomeActive() {
        guard !isStopped else { return }
        runAutomaticCheckIfNeeded(trigger: .automatic)
    }

    /// Test aid: waits for the in-flight automatic check (if any) to finish.
    func awaitCurrentCheck() async {
        await checkTask?.value
    }

    private func performAutomaticCheck(trigger: UpdateCheckTrigger) async {
        defer { isChecking = false }
        do {
            let result = try await checker.checkForUpdate()
            guard !Task.isCancelled, !isStopped else { return }
            switch result {
            case .upToDate:
                log("update.auto.check.upToDate")
            case .available(let release, let notes):
                log("update.auto.check.available")
                guard store.commitAutomaticUpdate(release: release, notes: notes) else {
                    log("update.auto.skipped.busy")
                    return
                }
                presentPrompt(for: release, notes: notes)
            }
        } catch {
            log("update.auto.check.failed")
        }
    }

    private func presentPrompt(for release: GitHubRelease, notes: String?) {
        guard !isStopped, !presenter.isPresenting else { return }
        installTriggered = false
        log("update.auto.prompt.presented")
        presenter.presentUpdate(
            currentVersion: AppVersionInfo.version,
            release: release,
            summary: Self.shortSummary(for: release, notes: notes),
            onInstall: { [weak self] in
                guard let self, !self.installTriggered else { return }
                self.installTriggered = true
                self.log("update.auto.prompt.install")
                self.installAction()
            },
            onLater: { [weak self] in
                self?.log("update.auto.prompt.later")
            }
        )
    }

    /// A short, non-Markdown summary for the small alert: the release name, or
    /// the first line of the release notes truncated, whichever is available.
    static func shortSummary(for release: GitHubRelease, notes: String?) -> String? {
        if let name = release.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        guard let notes, !notes.isEmpty else { return nil }
        let firstLine = notes
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let firstLine, !firstLine.isEmpty else { return nil }
        return String(firstLine.prefix(90))
    }

    private func noteCheckCompleted() {
        guard !isStopped else { return }
        markCheckedToday()
    }

    private var hasCheckedToday: Bool {
        guard let stored = defaults.object(forKey: Self.lastAutomaticCheckDayKey) as? Double else { return false }
        return calendar.isDate(Date(timeIntervalSince1970: stored), inSameDayAs: now())
    }

    private func markCheckedToday() {
        defaults.set(
            calendar.startOfDay(for: now()).timeIntervalSince1970,
            forKey: Self.lastAutomaticCheckDayKey
        )
    }
}
