import Darwin
import Foundation
import IOKit.ps

protocol MetricReader: AnyObject {
    var identifier: MetricIdentifier { get }
    var interval: TimeInterval { get }
    func read(previous: SystemSnapshot) throws -> MetricUpdate
}

enum MetricReaderError: LocalizedError {
    case mach(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .mach(let message), .unavailable(let message): return message
        }
    }
}

struct CPUTickSample: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

final class CPUReader: MetricReader {
    let identifier = MetricIdentifier.cpu
    let interval: TimeInterval = 2
    private var previousTicks: CPUTickSample?

    func read(previous: SystemSnapshot) throws -> MetricUpdate {
        let current = try readTicks()
        defer { previousTicks = current }
        guard let previousTicks else {
            return .cpu(CPUMetrics(total: 0, user: 0, system: 0))
        }
        return .cpu(Self.calculate(previous: previousTicks, current: current))
    }

    static func calculate(previous: CPUTickSample, current: CPUTickSample) -> CPUMetrics {
        let user = Double(current.user &- previous.user)
        let system = Double(current.system &- previous.system)
        let idle = Double(current.idle &- previous.idle)
        let nice = Double(current.nice &- previous.nice)
        let totalTicks = user + system + idle + nice
        guard totalTicks > 0 else { return CPUMetrics(total: 0, user: 0, system: 0) }
        let userFraction = (user + nice) / totalTicks
        let systemFraction = system / totalTicks
        return CPUMetrics(
            total: min(max(userFraction + systemFraction, 0), 1),
            user: min(max(userFraction, 0), 1),
            system: min(max(systemFraction, 0), 1)
        )
    }

    private func readTicks() throws -> CPUTickSample {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricReaderError.mach("host_statistics CPU failed: \(result)")
        }
        return CPUTickSample(
            user: load.cpu_ticks.0,
            system: load.cpu_ticks.1,
            idle: load.cpu_ticks.2,
            nice: load.cpu_ticks.3
        )
    }
}

struct MemoryPageCounts: Equatable {
    let active: UInt64
    let inactive: UInt64
    let speculative: UInt64
    let wired: UInt64
    let compressed: UInt64
    let purgeable: UInt64
    let external: UInt64
}

final class MemoryReader: MetricReader {
    let identifier = MetricIdentifier.memory
    let interval: TimeInterval = 2

    func read(previous: SystemSnapshot) throws -> MetricUpdate {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricReaderError.mach("host_statistics64 memory failed: \(result)")
        }

        let pages = MemoryPageCounts(
            active: UInt64(statistics.active_count),
            inactive: UInt64(statistics.inactive_count),
            speculative: UInt64(statistics.speculative_count),
            wired: UInt64(statistics.wire_count),
            compressed: UInt64(statistics.compressor_page_count),
            purgeable: UInt64(statistics.purgeable_count),
            external: UInt64(statistics.external_page_count)
        )
        let metrics = Self.calculate(
            pages: pages,
            pageSize: UInt64(vm_kernel_page_size),
            total: ProcessInfo.processInfo.physicalMemory,
            swap: readSwap(),
            pressure: readPressure()
        )
        return .memory(metrics)
    }

    static func calculate(
        pages: MemoryPageCounts,
        pageSize: UInt64,
        total: UInt64,
        swap: (used: UInt64, total: UInt64),
        pressure: MemoryPressure
    ) -> MemoryMetrics {
        func bytes(_ pages: UInt64) -> UInt64 { pages.multipliedReportingOverflow(by: pageSize).partialValue }
        let active = bytes(pages.active)
        let inactive = bytes(pages.inactive + pages.speculative)
        let wired = bytes(pages.wired)
        let compressed = bytes(pages.compressed)
        let cached = bytes(pages.purgeable + pages.external)
        let gross = active.addingReportingOverflow(inactive).partialValue
            .addingReportingOverflow(wired).partialValue
            .addingReportingOverflow(compressed).partialValue
        let used = min(gross > cached ? gross - cached : 0, total)
        return MemoryMetrics(
            total: total,
            used: used,
            free: total - used,
            active: active,
            inactive: inactive,
            wired: wired,
            compressed: compressed,
            cached: cached,
            swapUsed: swap.used,
            swapTotal: swap.total,
            pressure: pressure
        )
    }

    private func readPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    private func readSwap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }
}

final class DiskReader: MetricReader {
    let identifier = MetricIdentifier.disk
    let interval: TimeInterval = 30

    func read(previous: SystemSnapshot) throws -> MetricUpdate {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        guard let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            throw MetricReaderError.unavailable("Disk capacity is unavailable")
        }
        return .disk(DiskMetrics(total: total, used: total > free ? total - free : 0, free: free))
    }
}

struct NetworkByteSample: Equatable {
    let received: UInt64
    let sent: UInt64
    let timestamp: TimeInterval
}

final class NetworkReader: MetricReader {
    let identifier = MetricIdentifier.network
    let interval: TimeInterval = 2
    private var previousSample: NetworkByteSample?

    func read(previous: SystemSnapshot) throws -> MetricUpdate {
        let current = try readBytes()
        defer { previousSample = current }
        guard let previousSample else {
            return .network(NetworkMetrics(
                downloadRate: 0,
                uploadRate: 0,
                receivedBytes: current.received,
                sentBytes: current.sent
            ))
        }
        return .network(Self.calculate(previous: previousSample, current: current))
    }

    static func calculate(previous: NetworkByteSample, current: NetworkByteSample) -> NetworkMetrics {
        let elapsed = max(current.timestamp - previous.timestamp, 0.001)
        let receivedDelta = current.received >= previous.received ? current.received - previous.received : 0
        let sentDelta = current.sent >= previous.sent ? current.sent - previous.sent : 0
        return NetworkMetrics(
            downloadRate: Double(receivedDelta) / elapsed,
            uploadRate: Double(sentDelta) / elapsed,
            receivedBytes: current.received,
            sentBytes: current.sent
        )
    }

    private func readBytes() throws -> NetworkByteSample {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else {
            throw MetricReaderError.unavailable("getifaddrs failed")
        }
        defer { freeifaddrs(firstAddress) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = cursor {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp, !isLoopback,
               let address = interface.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let rawData = interface.pointee.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            cursor = interface.pointee.ifa_next
        }
        return NetworkByteSample(
            received: received,
            sent: sent,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }
}

final class BatteryReader: MetricReader {
    let identifier = MetricIdentifier.battery
    let interval: TimeInterval = 15

    func read(previous: SystemSnapshot) throws -> MetricUpdate {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            throw MetricReaderError.unavailable("Power source information is unavailable")
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  let type = description[kIOPSTypeKey as String] as? String,
                  type == kIOPSInternalBatteryType else { continue }

            let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue ?? 0
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            let charging = (description[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue ?? false
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutesValue = (description[minutesKey as String] as? NSNumber)?.intValue
            let minutes = minutesValue.flatMap { $0 >= 0 ? $0 : nil }
            return .battery(BatteryMetrics(
                isPresent: true,
                chargeFraction: maximum > 0 ? min(max(current / maximum, 0), 1) : nil,
                isCharging: charging,
                powerSource: state == kIOPSACPowerValue ? .ac : .battery,
                timeRemainingMinutes: minutes
            ))
        }

        return .battery(BatteryMetrics(
            isPresent: false,
            chargeFraction: nil,
            isCharging: false,
            powerSource: .ac,
            timeRemainingMinutes: nil
        ))
    }
}
