@MainActor
protocol SpeechSynthesisServicing: AnyObject {
    var activeTarget: TranslationSpeechTarget? { get }
    var stateDidChange: ((TranslationSpeechTarget?) -> Void)? { get set }

    @discardableResult
    func speak(
        _ text: String,
        languageIdentifier: String?,
        target: TranslationSpeechTarget
    ) -> Bool

    func stop()
}
