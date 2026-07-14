import Foundation

enum MetricIdentifier: String, CaseIterable, Hashable {
    case cpu
    case memory
    case disk
    case network
    case battery
}

struct CPUMetrics: Equatable {
    let total: Double
    let user: Double
    let system: Double
}

enum MemoryPressure: String, Equatable {
    case normal
    case warning
    case critical
}

struct MemoryMetrics: Equatable {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    let active: UInt64
    let inactive: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let pressure: MemoryPressure

    var fractionUsed: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}

struct DiskMetrics: Equatable {
    let total: UInt64
    let used: UInt64
    let free: UInt64

    var fractionUsed: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}

struct NetworkMetrics: Equatable {
    let downloadRate: Double
    let uploadRate: Double
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

enum PowerSource: String, Equatable {
    case battery
    case ac
    case unknown
}

struct BatteryMetrics: Equatable {
    let isPresent: Bool
    let chargeFraction: Double?
    let isCharging: Bool
    let powerSource: PowerSource
    let timeRemainingMinutes: Int?
}

struct MetricHistory: Equatable {
    static let limit = 60

    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var download: [Double] = []
    private(set) var upload: [Double] = []

    mutating func appendCPU(_ value: Double) { append(value, to: &cpu) }
    mutating func appendMemory(_ value: Double) { append(value, to: &memory) }
    mutating func appendNetwork(download: Double, upload: Double) {
        append(download, to: &self.download)
        append(upload, to: &self.upload)
    }

    private func append(_ value: Double, to values: inout [Double]) {
        values.append(value)
        if values.count > Self.limit {
            values.removeFirst(values.count - Self.limit)
        }
    }
}

struct SystemSnapshot: Equatable {
    var cpu: CPUMetrics?
    var memory: MemoryMetrics?
    var disk: DiskMetrics?
    var network: NetworkMetrics?
    var battery: BatteryMetrics?
    var history = MetricHistory()
    var unavailableMetrics: Set<MetricIdentifier> = []
    var lastUpdated: Date?
    var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime

    static let empty = SystemSnapshot()

    func isAvailable(_ identifier: MetricIdentifier) -> Bool {
        !unavailableMetrics.contains(identifier)
    }

    mutating func apply(_ update: MetricUpdate, at date: Date = Date()) {
        switch update {
        case .cpu(let metrics):
            cpu = metrics
            history.appendCPU(metrics.total)
            unavailableMetrics.remove(.cpu)
        case .memory(let metrics):
            memory = metrics
            history.appendMemory(metrics.fractionUsed)
            unavailableMetrics.remove(.memory)
        case .disk(let metrics):
            disk = metrics
            unavailableMetrics.remove(.disk)
        case .network(let metrics):
            network = metrics
            history.appendNetwork(download: metrics.downloadRate, upload: metrics.uploadRate)
            unavailableMetrics.remove(.network)
        case .battery(let metrics):
            battery = metrics
            unavailableMetrics.remove(.battery)
        }
        lastUpdated = date
        uptime = ProcessInfo.processInfo.systemUptime
    }

    mutating func markUnavailable(_ identifier: MetricIdentifier) {
        unavailableMetrics.insert(identifier)
    }
}

enum MetricUpdate: Equatable {
    case cpu(CPUMetrics)
    case memory(MemoryMetrics)
    case disk(DiskMetrics)
    case network(NetworkMetrics)
    case battery(BatteryMetrics)
}
