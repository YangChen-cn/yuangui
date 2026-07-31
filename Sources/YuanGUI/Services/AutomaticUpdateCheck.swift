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

/// The small environment surface needed before an automatic prompt is shown.
/// Keeping AppKit state behind this protocol makes the coordinator testable
/// without opening windows or changing the user's focus.
@MainActor
protocol UpdatePromptEnvironment: AnyObject {
    var isApplicationActive: Bool { get }
    var hasBlockingModalPresentation: Bool { get }
}

@MainActor
final class AppKitUpdatePromptEnvironment: UpdatePromptEnvironment {
    var isApplicationActive: Bool { NSApp.isActive }

    var hasBlockingModalPresentation: Bool {
        if NSApp.modalWindow != nil { return true }

        return NSApp.windows.contains { window in
            guard window.isVisible, !window.isMiniaturized else { return false }
            if window is NSSavePanel { return true }
            return window.attachedSheet != nil || window.sheetParent != nil
        }
    }
}

@MainActor
protocol UpdatePromptPresenting: AnyObject {
    var isPresenting: Bool { get }

    func presentUpdate(
        currentVersion: String,
        release: GitHubRelease,
        highlights: [String],
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onShowDetails: @escaping () -> Void
    )

    func dismiss()
}

/// Coordinates the once-per-natural-day automatic update check and prompt.
///
/// The coordinator owns only the automatic flow: daily frequency, task
/// lifecycle, concurrency guards, pending presentation, and persistence.
/// Manual checks keep going through `AppUpdateStore.check()`, which is never
/// blocked by the daily limit.
@MainActor
final class AutomaticUpdateCheckCoordinator {
    static let lastAutomaticCheckDayKey = "updates.lastAutomaticCheckDay"
    static let startupDelayNanoseconds: UInt64 = 2_500_000_000

    private struct PendingUpdate {
        let release: GitHubRelease
        let notes: String?
    }

    private let checker: UpdateChecking
    private let store: AppUpdateStore
    private let presenter: UpdatePromptPresenting
    private let environment: UpdatePromptEnvironment
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let installAction: () -> Void
    private let showDetailsAction: () -> Void
    private let startupDelay: Duration
    private let log: (String) -> Void

    private var activationObserver: NSObjectProtocol?
    private var sheetObserver: NSObjectProtocol?
    private var startupTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var stateCancellable: AnyCancellable?
    private var pendingUpdate: PendingUpdate?
    private var isChecking = false
    private var isStopped = false
    private var installTriggered = false
    private var startupDelayCompleted = false
    private var activationOccurredDuringStartup = false

    init(
        checker: UpdateChecking = AppUpdateService(),
        store: AppUpdateStore,
        presenter: UpdatePromptPresenting? = nil,
        environment: UpdatePromptEnvironment? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        startupDelay: Duration = .seconds(2.5),
        install: (() -> Void)? = nil,
        showDetails: @escaping () -> Void = {},
        log: @escaping (String) -> Void = AutomaticUpdateLog.log
    ) {
        self.checker = checker
        self.store = store
        self.presenter = presenter ?? UpdateAvailableWindowController()
        self.environment = environment ?? AppKitUpdatePromptEnvironment()
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.startupDelay = startupDelay
        self.installAction = install ?? { [weak store] in store?.installLatest() }
        self.showDetailsAction = showDetails
        self.log = log
    }

    /// Installs observers and schedules the launch-time check. Activation
    /// notifications received before the delay completes are recorded only;
    /// they cannot bypass the startup delay.
    func start() {
        guard !isStopped, activationObserver == nil else { return }

        startupDelayCompleted = false
        activationOccurredDuringStartup = false
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applicationDidBecomeActive()
            }
        }
        sheetObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndSheetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tryPresentPendingUpdate()
            }
        }

        // A successful manual check also counts as "checked today", so an
        // automatic request is not fired right after the user checked by hand.
        stateCancellable = store.$state
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, !self.isStopped else { return }
                    switch state {
                    case .available, .upToDate:
                        self.noteCheckCompleted()
                    case .downloading, .installing:
                        self.pendingUpdate = nil
                        if self.presenter.isPresenting { self.presenter.dismiss() }
                    default:
                        break
                    }
                }
            }

        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.startupDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, !self.isStopped else { return }
            self.startupDelayCompleted = true
            if self.activationOccurredDuringStartup {
                self.log("update.auto.startup.activationDeferred")
            }
            self.runAutomaticCheckIfNeeded(trigger: .automatic)
            self.tryPresentPendingUpdate()
        }
    }

    /// Cancels delayed and in-flight work, removes observers, and closes a
    /// visible prompt. No prompt can be presented after this call.
    func stop() {
        isStopped = true
        pendingUpdate = nil
        startupTask?.cancel()
        startupTask = nil
        checkTask?.cancel()
        checkTask = nil
        stateCancellable?.cancel()
        stateCancellable = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let sheetObserver {
            NotificationCenter.default.removeObserver(sheetObserver)
        }
        activationObserver = nil
        sheetObserver = nil
        if presenter.isPresenting { presenter.dismiss() }
    }

    /// The single entry point for an automatic check. It remains callable
    /// directly in unit tests; direct calls before `start()` intentionally skip
    /// the launch-only delay guard.
    func runAutomaticCheckIfNeeded(trigger: UpdateCheckTrigger = .automatic) {
        guard !isStopped, !isChecking else { return }
        if trigger == .automatic, activationObserver != nil, !startupDelayCompleted {
            activationOccurredDuringStartup = true
            log("update.auto.skipped.startupDelay")
            return
        }
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

    /// Called by the AppKit activation observer and intentionally kept small:
    /// activation may show an already-known pending update, but never makes a
    /// background update discoverable by stealing focus.
    private func applicationDidBecomeActive() {
        guard !isStopped else { return }
        guard startupDelayCompleted else {
            activationOccurredDuringStartup = true
            return
        }
        tryPresentPendingUpdate()
        runAutomaticCheckIfNeeded(trigger: .automatic)
    }

    /// Retries a pending update after an activation or sheet dismissal. This is
    /// intentionally event-driven; it does not poll with a timer.
    func tryPresentPendingUpdate() {
        guard !isStopped,
              (activationObserver == nil || startupDelayCompleted),
              let pendingUpdate
        else { return }
        guard !presenter.isPresenting, !store.isBusy else { return }
        guard environment.isApplicationActive else { return }
        guard !environment.hasBlockingModalPresentation else { return }

        self.pendingUpdate = nil
        presentPrompt(for: pendingUpdate.release, notes: pendingUpdate.notes)
    }

    /// Test aid: waits for the in-flight automatic check (if any) to finish.
    func awaitCurrentCheck() async {
        await checkTask?.value
    }

    private func performAutomaticCheck(trigger: UpdateCheckTrigger) async {
        _ = trigger
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
                pendingUpdate = PendingUpdate(release: release, notes: notes)
                tryPresentPendingUpdate()
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
            highlights: Self.highlights(for: release, notes: notes),
            onInstall: { [weak self] in
                guard let self, !self.installTriggered else { return }
                self.installTriggered = true
                self.pendingUpdate = nil
                self.log("update.auto.prompt.install")
                self.installAction()
            },
            onLater: { [weak self] in
                guard let self else { return }
                self.pendingUpdate = nil
                self.log("update.auto.prompt.later")
            },
            onShowDetails: { [weak self] in
                guard let self else { return }
                self.pendingUpdate = nil
                self.log("update.auto.prompt.details")
                self.showDetailsAction()
            }
        )
    }

    /// Extracts useful release content for the compact prompt. Release names
    /// are intentionally ignored because they commonly repeat the version.
    static func highlights(for release: GitHubRelease, notes: String?) -> [String] {
        let source = (notes?.isEmpty == false ? notes : nil) ?? release.body
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let rows = ReleaseNoteRow.parse(source)
        let bullets = rows.filter { $0.kind == .bullet }.map(\.text)
        let candidates = bullets.isEmpty ? rows.filter { $0.kind == .paragraph }.map(\.text) : bullets

        var result: [String] = []
        for candidate in candidates {
            let cleaned = cleanHighlight(candidate)
            guard !cleaned.isEmpty,
                  cleaned.caseInsensitiveCompare(release.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") != .orderedSame
            else { continue }
            result.append(truncateHighlight(cleaned))
            if result.count == 2 { break }
        }
        return result
    }

    private static func cleanHighlight(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"^[-*+•]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\d+[.)]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncateHighlight(_ value: String, limit: Int = 110) -> String {
        guard value.count > limit else { return value }
        let prefix = String(value.prefix(limit))
        if let boundary = prefix.lastIndex(where: { $0.isWhitespace }) {
            return prefix[..<boundary].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return prefix + "…"
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
