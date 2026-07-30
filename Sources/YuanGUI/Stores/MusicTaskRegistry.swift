import Foundation

@MainActor
final class MusicTaskRegistry {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var entries: [String: Entry] = [:]
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private(set) var generation: UInt64 = 0
    private(set) var isShuttingDown = false

    var activeTaskCount: Int { runningTasks.count }

    @discardableResult
    func launch(
        key: String,
        replacingExisting: Bool = true,
        operation: @escaping @MainActor (_ generation: UInt64) async -> Void
    ) -> Bool {
        guard !isShuttingDown else { return false }
        if let existing = entries[key] {
            guard replacingExisting else { return false }
            existing.task.cancel()
        }

        let token = UUID()
        let taskGeneration = generation
        let task = Task { @MainActor [weak self] in
            await operation(taskGeneration)
            guard let self,
                  self.runningTasks[token] != nil else {
                return
            }
            self.runningTasks[token] = nil
            if self.entries[key]?.token == token {
                self.entries[key] = nil
            }
        }
        let entry = Entry(token: token, task: task)
        entries[key] = entry
        runningTasks[token] = task
        return true
    }

    func cancel(key: String) {
        entries.removeValue(forKey: key)?.task.cancel()
    }

    func isCurrent(_ taskGeneration: UInt64) -> Bool {
        !isShuttingDown
            && !Task.isCancelled
            && generation == taskGeneration
    }

    func shutdown() async {
        guard !isShuttingDown else {
            let running = Array(runningTasks.values)
            for task in running {
                await task.value
            }
            return
        }

        isShuttingDown = true
        generation &+= 1
        let running = Array(runningTasks.values)
        running.forEach { $0.cancel() }
        for task in running {
            await task.value
        }
        entries.removeAll()
        runningTasks.removeAll()
    }
}
