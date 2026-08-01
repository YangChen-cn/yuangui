import AVFoundation

@MainActor
final class SystemSpeechSynthesisService: NSObject, SpeechSynthesisServicing {
    private var synthesizerStorage: AVSpeechSynthesizer?
    private var activeUtteranceID: ObjectIdentifier?

    private(set) var activeTarget: TranslationSpeechTarget?
    var stateDidChange: ((TranslationSpeechTarget?) -> Void)?

    @discardableResult
    func speak(
        _ text: String,
        languageIdentifier: String?,
        target: TranslationSpeechTarget
    ) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SystemSpeechVoiceResolver.voice(for: languageIdentifier)
        activeUtteranceID = ObjectIdentifier(utterance)
        updateActiveTarget(target)
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        activeUtteranceID = nil
        if let synthesizerStorage {
            synthesizerStorage.stopSpeaking(at: .immediate)
        }
        updateActiveTarget(nil)
    }

    deinit {
        synthesizerStorage?.delegate = nil
        synthesizerStorage?.stopSpeaking(at: .immediate)
    }

    private var synthesizer: AVSpeechSynthesizer {
        if let synthesizerStorage { return synthesizerStorage }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizerStorage = synthesizer
        return synthesizer
    }

    private func updateActiveTarget(_ target: TranslationSpeechTarget?) {
        guard target != activeTarget else { return }
        activeTarget = target
        stateDidChange?(target)
    }

    private func finishUtterance(with identifier: ObjectIdentifier) {
        guard activeUtteranceID == identifier else { return }
        activeUtteranceID = nil
        updateActiveTarget(nil)
    }
}

extension SystemSpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishUtterance(with: identifier)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishUtterance(with: identifier)
        }
    }
}
