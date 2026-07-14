import XCTest
@testable import YuanGUI

final class MetricReaderTests: XCTestCase {
    func testMonitoringProfilesOnlyScheduleNeededMetrics() {
        for identifier in MetricIdentifier.allCases {
            XCTAssertNil(MonitoringProfile.hidden.interval(for: identifier))
        }
        XCTAssertEqual(MonitoringProfile.companion.interval(for: .memory), 20)
        XCTAssertEqual(MonitoringProfile.companion.interval(for: .battery), 300)
        XCTAssertNil(MonitoringProfile.companion.interval(for: .cpu))
        XCTAssertNil(MonitoringProfile.companion.interval(for: .network))
        XCTAssertNil(MonitoringProfile.companion.interval(for: .disk))
        XCTAssertEqual(MonitoringProfile.live.interval(for: .cpu), 2)
        XCTAssertEqual(MonitoringProfile.live.interval(for: .memory), 2)
        XCTAssertEqual(MonitoringProfile.live.interval(for: .network), 2)
    }

    @MainActor
    func testSystemMonitorCombinesPetMiniAndDashboardDemand() {
        let monitor = SystemMonitor(coordinator: MetricsCoordinator(readers: []))
        XCTAssertEqual(monitor.profile, .hidden)
        monitor.setPetVisible(true)
        XCTAssertEqual(monitor.profile, .companion)
        monitor.setMiniStatusVisible(true)
        XCTAssertEqual(monitor.profile, .live)
        monitor.setPetVisible(false)
        XCTAssertEqual(monitor.profile, .hidden)
        monitor.setDashboardVisible(true)
        XCTAssertEqual(monitor.profile, .live)
        monitor.setDashboardVisible(false)
        XCTAssertEqual(monitor.profile, .hidden)
    }

    func testCoordinatorPausesHiddenAndRefreshesOnProfileChange() async throws {
        let memory = CountingMetricReader(identifier: .memory)
        let cpu = CountingMetricReader(identifier: .cpu)
        let coordinator = MetricsCoordinator(readers: [memory, cpu])
        coordinator.start { _ in }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(memory.readCount, 0)
        XCTAssertEqual(cpu.readCount, 0)

        coordinator.setProfile(.companion)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(memory.readCount, 1)
        XCTAssertEqual(cpu.readCount, 0)

        coordinator.setProfile(.live)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(memory.readCount, 2)
        XCTAssertEqual(cpu.readCount, 1)
        coordinator.stop()
    }

    func testCPUUsesTickDeltas() {
        let previous = CPUTickSample(user: 100, system: 40, idle: 300, nice: 10)
        let current = CPUTickSample(user: 150, system: 60, idle: 330, nice: 10)
        let result = CPUReader.calculate(previous: previous, current: current)

        XCTAssertEqual(result.user, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.system, 0.2, accuracy: 0.0001)
        XCTAssertEqual(result.total, 0.7, accuracy: 0.0001)
    }

    func testCPUHandlesCounterWrap() {
        let previous = CPUTickSample(user: UInt32.max - 5, system: 20, idle: 40, nice: 0)
        let current = CPUTickSample(user: 4, system: 30, idle: 50, nice: 0)
        let result = CPUReader.calculate(previous: previous, current: current)

        XCTAssertTrue(result.total.isFinite)
        XCTAssertGreaterThanOrEqual(result.total, 0)
        XCTAssertLessThanOrEqual(result.total, 1)
    }

    func testMemoryFormulaSubtractsCache() {
        let pages = MemoryPageCounts(
            active: 10,
            inactive: 8,
            speculative: 2,
            wired: 4,
            compressed: 3,
            purgeable: 2,
            external: 1
        )
        let result = MemoryReader.calculate(
            pages: pages,
            pageSize: 100,
            total: 10_000,
            swap: (used: 500, total: 2_000),
            pressure: .warning
        )

        XCTAssertEqual(result.used, 2_400)
        XCTAssertEqual(result.free, 7_600)
        XCTAssertEqual(result.cached, 300)
        XCTAssertEqual(result.swapUsed, 500)
        XCTAssertEqual(result.pressure, .warning)
    }

    func testNetworkRateUsesElapsedTime() {
        let previous = NetworkByteSample(received: 1_000, sent: 2_000, timestamp: 10)
        let current = NetworkByteSample(received: 5_000, sent: 3_000, timestamp: 12)
        let result = NetworkReader.calculate(previous: previous, current: current)

        XCTAssertEqual(result.downloadRate, 2_000, accuracy: 0.001)
        XCTAssertEqual(result.uploadRate, 500, accuracy: 0.001)
    }

    func testSnapshotHistoryIsBounded() {
        var snapshot = SystemSnapshot.empty
        for index in 0..<75 {
            snapshot.apply(.cpu(CPUMetrics(total: Double(index) / 100, user: 0, system: 0)))
            snapshot.apply(.memory(MemoryMetrics(
                total: 100,
                used: UInt64(index),
                free: UInt64(100 - index),
                active: 0,
                inactive: 0,
                wired: 0,
                compressed: 0,
                cached: 0,
                swapUsed: 0,
                swapTotal: 0,
                pressure: .normal
            )))
        }

        XCTAssertEqual(snapshot.history.cpu.count, MetricHistory.limit)
        XCTAssertEqual(snapshot.history.memory.count, MetricHistory.limit)
        XCTAssertEqual(snapshot.history.cpu.last ?? -1, 0.74, accuracy: 0.0001)
    }
}

private final class CountingMetricReader: MetricReader {
    let identifier: MetricIdentifier
    let interval: TimeInterval = 1
    private let lock = NSLock()
    private var count = 0

    init(identifier: MetricIdentifier) {
        self.identifier = identifier
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func read(previous: SystemSnapshot) throws -> MetricUpdate {
        lock.lock()
        count += 1
        lock.unlock()
        switch identifier {
        case .cpu:
            return .cpu(CPUMetrics(total: 0, user: 0, system: 0))
        case .memory:
            return .memory(MemoryMetrics(
                total: 1, used: 0, free: 1, active: 0, inactive: 0, wired: 0,
                compressed: 0, cached: 0, swapUsed: 0, swapTotal: 0, pressure: .normal
            ))
        default:
            throw MetricReaderError.unavailable("测试未实现")
        }
    }
}
