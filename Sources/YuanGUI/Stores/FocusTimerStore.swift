import Combine
import Foundation

@MainActor
final class FocusTimerStore: ObservableObject {
    enum State: Equatable { case idle, running, paused, completed }

    @Published private(set) var state: State = .idle
    @Published private(set) var remainingSeconds = 25 * 60
    @Published private(set) var durationMinutes: Int

    static let minimumDurationMinutes = 1
    static let maximumDurationMinutes = 180

    private let pet: PetStore
    private let defaults: UserDefaults
    private var timer: AnyCancellable?
    private var deadline: Date?

    init(pet: PetStore, defaults: UserDefaults = .standard) {
        self.pet = pet
        self.defaults = defaults
        let saved = defaults.object(forKey: "focusDurationMinutes") as? Int ?? 25
        let initialDuration = Self.clampedDuration(saved)
        self.durationMinutes = initialDuration
        self.remainingSeconds = initialDuration * 60
    }

    var timeText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var progress: Double {
        let total = max(durationMinutes * 60, 1)
        return 1 - Double(remainingSeconds) / Double(total)
    }

    var statusTitle: String {
        switch state {
        case .idle: return "准备专注"
        case .running: return "安静陪伴中"
        case .paused: return "已暂停"
        case .completed: return "完成一轮"
        }
    }

    func setDurationMinutes(_ minutes: Int) {
        let clamped = Self.clampedDuration(minutes)
        if durationMinutes != clamped {
            durationMinutes = clamped
        }
        defaults.set(clamped, forKey: "focusDurationMinutes")
        if state == .idle || state == .completed {
            remainingSeconds = clamped * 60
        }
    }

    func start(minutes: Int) {
        setDurationMinutes(minutes)
        start()
    }

    func start() {
        if state == .idle || state == .completed { remainingSeconds = durationMinutes * 60 }
        state = .running
        deadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        pet.beginFocus()
        startTimer()
    }

    func pause() {
        guard state == .running else { return }
        updateRemaining()
        state = .paused
        deadline = nil
        timer = nil
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        deadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        startTimer()
    }

    func stop() {
        timer = nil
        deadline = nil
        state = .idle
        remainingSeconds = durationMinutes * 60
        pet.endFocus(completed: false)
    }

    private func startTimer() {
        timer = Timer.publish(every: 1, tolerance: 0.18, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        updateRemaining()
        guard remainingSeconds <= 0 else { return }
        timer = nil
        deadline = nil
        state = .completed
        pet.endFocus(completed: true)
    }

    private func updateRemaining() {
        guard let deadline else { return }
        remainingSeconds = max(Int(deadline.timeIntervalSinceNow.rounded(.up)), 0)
    }

    private static func clampedDuration(_ minutes: Int) -> Int {
        min(max(minutes, minimumDurationMinutes), maximumDurationMinutes)
    }
}
