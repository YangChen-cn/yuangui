import AppKit
import CoreAudio
import Foundation
import OSLog

struct ExternalAudioProcess: Equatable {
    let processID: pid_t
    let bundleIdentifier: String?
}

@MainActor
protocol ExternalAudioActivityMonitoring: AnyObject {
    var onActivityChanged: ((Bool) -> Void)? { get set }
    func start(excluding: @escaping (ExternalAudioProcess) -> Bool)
    func stop()
}

/// Watches Core Audio process output events and keeps a low-frequency poll only
/// as a fallback for drivers that miss a property-change notification.
@MainActor
final class ExternalAudioActivityMonitor: ExternalAudioActivityMonitoring {
    var onActivityChanged: ((Bool) -> Void)?
    private var timer: Timer?
    private var shouldExclude: ((ExternalAudioProcess) -> Bool)?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processOutputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var lastReportedExternalOutput: Bool?
    private static let logger = Logger(subsystem: "com.yuangui.app", category: "ExternalAudioMonitor")

    func start(excluding: @escaping (ExternalAudioProcess) -> Bool) {
        shouldExclude = excluding
        guard timer == nil else { return }
        installProcessListListener()
        reconcileProcessOutputListeners()
        poll(origin: "start")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll(origin: "fallback-poll") }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        removeProcessListeners()
        shouldExclude = nil
    }

    private func poll(origin: String) {
        reconcileProcessOutputListeners()
        let activeProcesses = processObjectIDs().compactMap { objectID -> ExternalAudioProcess? in
            guard isRunningOutput(objectID),
                  let process = process(for: objectID),
                  !Self.isSystemAudioProcess(process),
                  !(shouldExclude?(process) ?? false) else { return nil }
            return process
        }
        let hasExternalOutput = !activeProcesses.isEmpty
        if lastReportedExternalOutput != hasExternalOutput {
            let processLabels = activeProcesses.map { $0.bundleIdentifier ?? "pid:\($0.processID)" }.joined(separator: ",")
            Self.logger.info("raw output changed active=\(hasExternalOutput, privacy: .public) origin=\(origin, privacy: .public) processes=\(processLabels, privacy: .public)")
            lastReportedExternalOutput = hasExternalOutput
        }
        onActivityChanged?(hasExternalOutput)
    }

    private func installProcessListListener() {
        guard processListListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.reconcileProcessOutputListeners()
                self?.poll(origin: "process-list-event")
            }
        }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
        ) == noErr else { return }
        processListListener = listener
    }

    private func reconcileProcessOutputListeners() {
        let currentProcessIDs = Set(processObjectIDs())
        let removedListeners = processOutputListeners.filter { !currentProcessIDs.contains($0.key) }
        for (objectID, listener) in removedListeners {
            removeRunningOutputListener(listener, from: objectID)
            processOutputListeners.removeValue(forKey: objectID)
        }
        for objectID in currentProcessIDs where processOutputListeners[objectID] == nil {
            installRunningOutputListener(on: objectID)
        }
    }

    private func installRunningOutputListener(on objectID: AudioObjectID) {
        var address = runningOutputAddress
        guard AudioObjectHasProperty(objectID, &address) else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.poll(origin: "output-event") }
        }
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, .main, listener) == noErr else { return }
        processOutputListeners[objectID] = listener
    }

    private func removeProcessListeners() {
        if let processListListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, processListListener
            )
            self.processListListener = nil
        }
        for (objectID, listener) in processOutputListeners {
            removeRunningOutputListener(listener, from: objectID)
        }
        processOutputListeners.removeAll()
    }

    private func removeRunningOutputListener(
        _ listener: @escaping AudioObjectPropertyListenerBlock,
        from objectID: AudioObjectID
    ) {
        var address = runningOutputAddress
        AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, listener)
    }

    private var runningOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount
        ) == noErr else { return [] }
        let count = Int(byteCount) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount, &ids
        ) == noErr else { return [] }
        return ids
    }

    private func process(for objectID: AudioObjectID) -> ExternalAudioProcess? {
        guard let rawPID = uint32Property(kAudioProcessPropertyPID, for: objectID), rawPID > 0 else {
            return nil
        }
        let processID = pid_t(rawPID)
        return ExternalAudioProcess(
            processID: processID,
            bundleIdentifier: stringProperty(kAudioProcessPropertyBundleID, for: objectID)
                ?? NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
        )
    }

    private func isRunningOutput(_ objectID: AudioObjectID) -> Bool {
        uint32Property(kAudioProcessPropertyIsRunningOutput, for: objectID) == 1
    }

    private func uint32Property(_ selector: AudioObjectPropertySelector, for objectID: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &byteCount, &value) == noErr else {
            return nil
        }
        return value
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, for objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &byteCount, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }

    private static func isSystemAudioProcess(_ process: ExternalAudioProcess) -> Bool {
        guard let bundleIdentifier = process.bundleIdentifier else { return true }
        return systemBundleIdentifiers.contains(bundleIdentifier)
    }

    private static let systemBundleIdentifiers: Set<String> = [
        "com.apple.audio.coreaudiod",
        "com.apple.SystemUIServer",
        "com.apple.notificationcenterui",
        "com.apple.usernotifications.usernotificationd",
        "com.apple.usernoted"
    ]
}
