import Combine
import Foundation
import IOKit.ps

enum MonitoringProfile: Int, Comparable, Equatable {
    case hidden
    case companion
    case live

    static func < (lhs: MonitoringProfile, rhs: MonitoringProfile) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func interval(for identifier: MetricIdentifier) -> TimeInterval? {
        switch self {
        case .hidden:
            return nil
        case .companion:
            switch identifier {
            case .memory: return 20
            case .battery: return 300
            case .cpu, .disk, .network: return nil
            }
        case .live:
            switch identifier {
            case .cpu, .memory, .network: return 2
            case .disk, .battery: return 60
            }
        }
    }
}

final class MetricsCoordinator {
    typealias UpdateHandler = (SystemSnapshot) -> Void

    private let queue = DispatchQueue(label: "com.yang.yuangui.metrics", qos: .utility)
    private let readers: [MetricReader]
    private var timer: DispatchSourceTimer?
    private var nextRead: [MetricIdentifier: Date] = [:]
    private var snapshot = SystemSnapshot.empty
    private var profile: MonitoringProfile = .hidden
    private var updateHandler: UpdateHandler?

    init(readers: [MetricReader] = [CPUReader(), MemoryReader(), DiskReader(), NetworkReader(), BatteryReader()]) {
        self.readers = readers
    }

    func start(updateHandler: @escaping UpdateHandler) {
        queue.async {
            guard self.timer == nil else { return }
            self.updateHandler = updateHandler
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
            self.scheduleNextWake()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.nextRead.removeAll()
            self.updateHandler = nil
        }
    }

    func setProfile(_ profile: MonitoringProfile) {
        queue.async {
            guard self.profile != profile else { return }
            self.profile = profile
            self.nextRead.removeAll()
            self.tick()
        }
    }

    func refresh(_ identifier: MetricIdentifier? = nil) {
        queue.async {
            if let identifier {
                guard self.profile.interval(for: identifier) != nil else { return }
                self.nextRead[identifier] = .distantPast
            } else {
                self.nextRead.removeAll()
            }
            self.tick()
        }
    }

    private func tick(now: Date = Date()) {
        guard profile != .hidden else {
            scheduleNextWake()
            return
        }

        var didReadMetric = false
        for reader in readers {
            guard let interval = profile.interval(for: reader.identifier) else {
                nextRead.removeValue(forKey: reader.identifier)
                continue
            }
            if let next = nextRead[reader.identifier], next > now { continue }
            didReadMetric = true
            do {
                snapshot.apply(try reader.read(previous: snapshot), at: now)
            } catch {
                snapshot.markUnavailable(reader.identifier)
            }
            nextRead[reader.identifier] = now.addingTimeInterval(interval)
        }
        if didReadMetric {
            updateHandler?(snapshot)
        }
        scheduleNextWake(now: now)
    }

    private func scheduleNextWake(now: Date = Date()) {
        guard let timer else { return }
        let dueDates = readers.compactMap { reader -> Date? in
            guard profile.interval(for: reader.identifier) != nil else { return nil }
            return nextRead[reader.identifier] ?? now
        }
        guard let next = dueDates.min() else {
            timer.schedule(deadline: .distantFuture)
            return
        }
        let delay = max(next.timeIntervalSince(now), 0.01)
        let leeway = min(max(delay * 0.15, 0.1), 2)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(Int(leeway * 1_000)))
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty
    @Published private(set) var profile: MonitoringProfile = .hidden

    private let coordinator: MetricsCoordinator
    private var isStarted = false
    private var petVisible = false
    private var miniStatusVisible = false
    private var dashboardVisible = false
    private var powerNotificationSource: CFRunLoopSource?

    init(coordinator: MetricsCoordinator = MetricsCoordinator()) {
        self.coordinator = coordinator
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        coordinator.start { [weak self] snapshot in
            DispatchQueue.main.async { self?.snapshot = snapshot }
        }
        installPowerNotifications()
        updateProfile()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        if let powerNotificationSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerNotificationSource, .commonModes)
            self.powerNotificationSource = nil
        }
        coordinator.stop()
    }

    func setPetVisible(_ visible: Bool) {
        petVisible = visible
        updateProfile()
    }

    func setMiniStatusVisible(_ visible: Bool) {
        miniStatusVisible = visible
        updateProfile()
    }

    func setDashboardVisible(_ visible: Bool) {
        dashboardVisible = visible
        updateProfile()
    }

    func refresh() {
        coordinator.refresh()
    }

    private func updateProfile() {
        let newProfile: MonitoringProfile
        if dashboardVisible || (petVisible && miniStatusVisible) {
            newProfile = .live
        } else if petVisible {
            newProfile = .companion
        } else {
            newProfile = .hidden
        }
        guard profile != newProfile else { return }
        profile = newProfile
        coordinator.setProfile(newProfile)
    }

    private func installPowerNotifications() {
        guard powerNotificationSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.coordinator.refresh(.battery)
            }
        }, context)?.takeRetainedValue() else { return }
        powerNotificationSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
