import XCTest
@testable import YuanGUI

final class MetricReaderTests: XCTestCase {
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
