import Combine
import Foundation
import OSLog

@MainActor
protocol ExternalAudioPlaybackControlling: AnyObject {
    var onExternalAudioResumeCancelled: (() -> Void)? { get set }
    var onExternalAudioManualControl: (() -> Void)? { get set }
    var blocksAutomaticPlaybackForExternalAudio: (() -> Bool)? { get set }
    func pauseForExternalAudio()
    func resumeAfterExternalAudio()
    func cancelExternalAudioResume()
}

extension MusicFeature: ExternalAudioPlaybackControlling {}

/// Turns raw Core Audio activity samples into the app's interruption policy.
@MainActor
final class ExternalAudioInterruptionController: ObservableObject {
    static let enabledDefaultsKey = "musicPauseForExternalAudio"
    static let resumeDefaultsKey = "musicResumeAfterExternalAudio"
    static let pauseDelay: TimeInterval = 1
    static let resumeDelay: TimeInterval = 2.5

    private let playback: any ExternalAudioPlaybackControlling
    private let monitor: any ExternalAudioActivityMonitoring
    private let defaults: UserDefaults
    private let sourceProvider: () -> MusicSource?
    @Published private(set) var isEnabled: Bool
    @Published private(set) var resumesAfterExternalAudio: Bool
    private var started = false
    private var activeSince: Date?
    private var inactiveSince: Date?
    private var hasRequestedAutomaticPause = false
    private var isExternalAudioSessionActive = false
    private var hasManualOverrideInCurrentSession = false
    private static let logger = Logger(subsystem: "com.yuangui.app", category: "ExternalAudioInterruption")

    convenience init(
        music: MusicFeature,
        defaults: UserDefaults = .standard
    ) {
        self.init(music: music, monitor: ExternalAudioActivityMonitor(), defaults: defaults)
    }

    init(
        music: MusicFeature,
        monitor: any ExternalAudioActivityMonitoring,
        defaults: UserDefaults = .standard
    ) {
        playback = music
        self.monitor = monitor
        self.defaults = defaults
        sourceProvider = { [weak music] in music?.playbackSource }
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        resumesAfterExternalAudio = defaults.object(forKey: Self.resumeDefaultsKey) == nil
            || defaults.bool(forKey: Self.resumeDefaultsKey)
        music.onExternalAudioResumeCancelled = { [weak self] in self?.cancelRecoveryEligibility() }
        music.onExternalAudioManualControl = { [weak self] in self?.recordManualControl() }
        music.blocksAutomaticPlaybackForExternalAudio = { [weak self] in self?.blocksAutomaticPlayback ?? false }
        monitor.onActivityChanged = { [weak self] active in self?.receiveActivity(isActive: active) }
    }

    init(
        playback: any ExternalAudioPlaybackControlling,
        monitor: any ExternalAudioActivityMonitoring,
        defaults: UserDefaults,
        sourceProvider: @escaping () -> MusicSource?
    ) {
        self.playback = playback
        self.monitor = monitor
        self.defaults = defaults
        self.sourceProvider = sourceProvider
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        resumesAfterExternalAudio = defaults.object(forKey: Self.resumeDefaultsKey) == nil
            || defaults.bool(forKey: Self.resumeDefaultsKey)
        playback.onExternalAudioResumeCancelled = { [weak self] in self?.cancelRecoveryEligibility() }
        playback.onExternalAudioManualControl = { [weak self] in self?.recordManualControl() }
        playback.blocksAutomaticPlaybackForExternalAudio = { [weak self] in self?.blocksAutomaticPlayback ?? false }
        monitor.onActivityChanged = { [weak self] active in self?.receiveActivity(isActive: active) }
    }

    func start() {
        guard !started else { return }
        started = true
        startMonitoringIfEnabled()
    }

    func stop() {
        started = false
        monitor.stop()
        resetInterruption(cancelResume: true)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            resetInterruption(cancelResume: true)
            startMonitoringIfEnabled()
        } else {
            monitor.stop()
            resetInterruption(cancelResume: true)
        }
    }

    func setResumesAfterExternalAudio(_ enabled: Bool) {
        resumesAfterExternalAudio = enabled
        defaults.set(enabled, forKey: Self.resumeDefaultsKey)
        if !enabled, hasRequestedAutomaticPause {
            playback.cancelExternalAudioResume()
            hasRequestedAutomaticPause = false
        }
    }

    func receiveActivity(isActive: Bool, at date: Date = Date()) {
        guard isEnabled else { return }
        if isActive {
            self.inactiveSince = nil
            if !isExternalAudioSessionActive {
                isExternalAudioSessionActive = true
                hasManualOverrideInCurrentSession = false
                activeSince = date
                Self.logger.info("external audio session started")
            } else if activeSince == nil {
                activeSince = date
            }
            guard !hasManualOverrideInCurrentSession,
                  !hasRequestedAutomaticPause,
                  let activeSince,
                  date.timeIntervalSince(activeSince) >= Self.pauseDelay else { return }
            hasRequestedAutomaticPause = true
            Self.logger.info("automatic pause requested after sustained external output")
            playback.pauseForExternalAudio()
        } else {
            activeSince = nil
            guard isExternalAudioSessionActive else { return }
            if inactiveSince == nil {
                inactiveSince = date
                Self.logger.info("external output became inactive; starting resume debounce")
            }
            guard let inactiveSince,
                  date.timeIntervalSince(inactiveSince) >= Self.resumeDelay else { return }
            if hasRequestedAutomaticPause {
                hasRequestedAutomaticPause = false
                if resumesAfterExternalAudio, !hasManualOverrideInCurrentSession {
                    Self.logger.info("automatic resume requested after stable inactivity")
                    playback.resumeAfterExternalAudio()
                } else {
                    Self.logger.info("automatic resume suppressed by setting or manual override")
                    playback.cancelExternalAudioResume()
                }
            }
            endExternalAudioSession()
        }
    }

    private func startMonitoringIfEnabled() {
        guard started, isEnabled else { return }
        monitor.start { [weak self] process in self?.shouldExclude(process) ?? true }
    }

    private func shouldExclude(_ process: ExternalAudioProcess) -> Bool {
        if process.processID == ProcessInfo.processInfo.processIdentifier { return true }
        if let bundleIdentifier = Bundle.main.bundleIdentifier, process.bundleIdentifier == bundleIdentifier {
            return true
        }
        return sourceProvider() == .appleMusic && process.bundleIdentifier == "com.apple.Music"
    }

    private func cancelRecoveryEligibility() {
        hasRequestedAutomaticPause = false
        inactiveSince = nil
    }

    private var blocksAutomaticPlayback: Bool {
        isExternalAudioSessionActive
    }

    private func recordManualControl() {
        guard isExternalAudioSessionActive else { return }
        Self.logger.info("manual music control overrides current external audio session")
        hasManualOverrideInCurrentSession = true
        hasRequestedAutomaticPause = false
        inactiveSince = nil
    }

    private func endExternalAudioSession() {
        Self.logger.info("external audio session ended")
        activeSince = nil
        inactiveSince = nil
        hasRequestedAutomaticPause = false
        hasManualOverrideInCurrentSession = false
        isExternalAudioSessionActive = false
    }

    private func resetInterruption(cancelResume: Bool) {
        activeSince = nil
        inactiveSince = nil
        hasRequestedAutomaticPause = false
        hasManualOverrideInCurrentSession = false
        isExternalAudioSessionActive = false
        if cancelResume { playback.cancelExternalAudioResume() }
    }
}
