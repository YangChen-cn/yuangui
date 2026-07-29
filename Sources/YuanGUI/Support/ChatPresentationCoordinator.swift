import Foundation

@MainActor
final class ChatPresentationCoordinator: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case presenting
        case presented
        case dismissing
    }

    static let contentAnimationDuration: TimeInterval = 0.14

    @Published private(set) var phase: Phase = .hidden

    var keepsExpandedLayout: Bool { phase != .hidden }
    var showsChatLayer: Bool { phase != .hidden }
    var showsChatContent: Bool { phase == .presented }

    var prepareExpandedLayout: (() -> Void)?
    var collapseToCompactLayout: (() -> Void)?
    var setPetChatting: ((Bool) -> Void)?
    var focusChatInput: (() -> Void)?

    private let delay: (Duration) async throws -> Void
    private var transitionTask: Task<Void, Never>?
    private var generation: UInt = 0

    init(
        delay: @escaping (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.delay = delay
    }

    func present(reduceMotion: Bool) {
        generation &+= 1
        let currentGeneration = generation
        transitionTask?.cancel()
        transitionTask = nil

        prepareExpandedLayout?()
        phase = .presenting
        setPetChatting?(true)

        transitionTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.generation == currentGeneration,
                  self.phase == .presenting else { return }
            self.phase = .presented
            if !reduceMotion {
                await Task.yield()
            }
            guard !Task.isCancelled,
                  self.generation == currentGeneration,
                  self.phase == .presented else { return }
            self.focusChatInput?()
            self.transitionTask = nil
        }
    }

    func dismiss(reduceMotion: Bool) {
        guard phase != .hidden else { return }
        generation &+= 1
        let currentGeneration = generation
        transitionTask?.cancel()
        phase = .dismissing

        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if reduceMotion {
                await Task.yield()
            } else {
                do {
                    try await self.delay(.seconds(Self.contentAnimationDuration))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  self.generation == currentGeneration,
                  self.phase == .dismissing else { return }
            self.phase = .hidden
            self.collapseToCompactLayout?()
            await Task.yield()
            guard !Task.isCancelled,
                  self.generation == currentGeneration,
                  self.phase == .hidden else { return }
            self.setPetChatting?(false)
            self.transitionTask = nil
        }
    }

    func cancelTransitions() {
        generation &+= 1
        transitionTask?.cancel()
        transitionTask = nil
    }
}
