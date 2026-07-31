import Foundation
import Network

protocol UpdateNetworkStatusProviding: Sendable {
    func isClearlyOffline() -> Bool
}

/// `NWPathMonitor` is deliberately used only for the obvious offline case.
/// A satisfied path does not imply that either update host is reachable.
final class NWPathMonitorStatusProvider: UpdateNetworkStatusProviding, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let lock = NSLock()
    private var status: NWPath.Status = .requiresConnection

    init() {
        monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.yang.yuangui.update-network-status")
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.status = path.status
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    func isClearlyOffline() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return status == .unsatisfied
    }
}
