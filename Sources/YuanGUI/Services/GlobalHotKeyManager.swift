import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case invalid(String)
    case duplicate
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        case .duplicate: "快捷工具不能使用相同的快捷键。"
        case let .registrationFailed(status): "快捷键已被其他应用占用，或系统拒绝注册（\(status)）。"
        }
    }
}

@MainActor
final class GlobalHotKeyManager {
    private var eventHandler: EventHandlerRef?
    private var registrations: [QuickToolAction: EventHotKeyRef] = [:]
    private var bindings: [QuickToolAction: HotKeyBinding] = [:]
    private var actionsByID: [UInt32: QuickToolAction] = [:]
    private let handler: (QuickToolAction) -> Void
    private let signature: OSType = 0x59554749 // YUGI

    init(handler: @escaping (QuickToolAction) -> Void) {
        self.handler = handler
    }

    deinit {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func start(bindings: [QuickToolAction: HotKeyBinding]) throws {
        let configuredBindings = QuickToolAction.allCases.compactMap { bindings[$0] }
        for (index, binding) in configuredBindings.enumerated()
        where configuredBindings.dropFirst(index + 1).contains(binding) {
            throw GlobalHotKeyError.duplicate
        }
        if eventHandler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, context in
                    guard let event, let context else { return OSStatus(eventNotHandledErr) }
                    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(context).takeUnretainedValue()
                    var hotKeyID = EventHotKeyID()
                    let result = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard result == noErr else { return result }
                    Task { @MainActor in manager.fire(id: hotKeyID.id) }
                    return noErr
                },
                1,
                &type,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else { throw GlobalHotKeyError.registrationFailed(status) }
        }

        do {
            for action in QuickToolAction.allCases {
                if let binding = bindings[action] {
                    try register(binding, for: action)
                }
            }
        } catch {
            stop()
            throw error
        }
    }

    func update(_ binding: HotKeyBinding, for action: QuickToolAction, otherBindings: [HotKeyBinding]) throws {
        if let message = binding.validationMessage { throw GlobalHotKeyError.invalid(message) }
        guard !otherBindings.contains(binding) else { throw GlobalHotKeyError.duplicate }

        let previousReference = registrations[action]
        let previousBinding = bindings[action]
        if let previousReference { UnregisterEventHotKey(previousReference) }
        registrations[action] = nil

        do {
            try register(binding, for: action)
        } catch {
            if let previousBinding {
                try? register(previousBinding, for: action)
            }
            throw error
        }
    }

    func stop() {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        registrations.removeAll()
        bindings.removeAll()
        actionsByID.removeAll()
    }

    private func register(_ binding: HotKeyBinding, for action: QuickToolAction) throws {
        if let message = binding.validationMessage { throw GlobalHotKeyError.invalid(message) }
        let id: UInt32
        switch action {
        case .regionScreenshot: id = 1
        case .translateSelection: id = 2
        case .screenshotTranslation: id = 3
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers.carbonValue,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        guard status == noErr, let reference else { throw GlobalHotKeyError.registrationFailed(status) }
        registrations[action] = reference
        bindings[action] = binding
        actionsByID[id] = action
    }

    private func fire(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        handler(action)
    }
}
