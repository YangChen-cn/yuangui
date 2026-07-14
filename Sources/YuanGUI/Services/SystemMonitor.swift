import Combine
import Foundation

final class MetricsCoordinator {
    typealias UpdateHandler = (SystemSnapshot) -> Void

    private let queue = DispatchQueue(label: "com.yang.yuangui.metrics", qos: .utility)
    private let readers: [MetricReader]
    private var timer: DispatchSourceTimer?
    private var nextRead: [MetricIdentifier: Date] = [:]
    private var snapshot = SystemSnapshot.empty
    private var isVisible = true
    private var updateHandler: UpdateHandler?

    init(readers: [MetricReader] = [CPUReader(), MemoryReader(), DiskReader(), NetworkReader(), BatteryReader()]) {
        self.readers = readers
    }

    func start(updateHandler: @escaping UpdateHandler) {
        queue.async {
            guard self.timer == nil else { return }
            self.updateHandler = updateHandler
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.updateHandler = nil
        }
    }

    func setVisible(_ visible: Bool) {
        queue.async {
            self.isVisible = visible
            if visible {
                self.nextRead.removeAll()
                self.tick()
            }
        }
    }

    func refresh() {
        queue.async {
            self.nextRead.removeAll()
            self.tick()
        }
    }

    private func tick(now: Date = Date()) {
        var didReadMetric = false
        for reader in readers {
            if let next = nextRead[reader.identifier], next > now { continue }
            didReadMetric = true
            do {
                snapshot.apply(try reader.read(previous: snapshot), at: now)
            } catch {
                snapshot.markUnavailable(reader.identifier)
            }
            let multiplier = isVisible ? 1.0 : 4.0
            nextRead[reader.identifier] = now.addingTimeInterval(reader.interval * multiplier)
        }
        if didReadMetric {
            updateHandler?(snapshot)
        }
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty
    private let coordinator: MetricsCoordinator
    private var isStarted = false

    init(coordinator: MetricsCoordinator = MetricsCoordinator()) {
        self.coordinator = coordinator
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        coordinator.start { [weak self] snapshot in
            DispatchQueue.main.async { self?.snapshot = snapshot }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        coordinator.stop()
    }

    func setPetVisible(_ visible: Bool) {
        coordinator.setVisible(visible)
    }

    func refresh() {
        coordinator.refresh()
    }
}
