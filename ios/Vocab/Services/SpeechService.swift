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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        synthesizer.speak(utterance)
    }
}
