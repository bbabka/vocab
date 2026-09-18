import AVFoundation
import Foundation

/// On-device TTS (no stored audio, no network) — a single shared synthesizer
/// so views don't each spin up their own. `languageCode` accepts a bare
/// ISO 639-1 code (`WordCollection.targetLanguage`'s own format);
/// `AVSpeechSynthesisVoice` resolves it to that language's default voice.
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, languageCode: String) {
        guard !text.isEmpty else { return }
        // A second tap on "Speak" before the first pronunciation finishes
        // otherwise starts a new utterance while the previous one is still
        // mid-flight — overlapping requests like that are the usual trigger
        // for AVSpeechSynthesizer's internal "accumulator"/"token" log spam
        // (harmless, but avoidable). `.immediate` cuts the old utterance
        // off outright rather than waiting for a word boundary, since the
        // user's intent here is "restart," not "queue after."
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        synthesizer.speak(utterance)
    }
}
