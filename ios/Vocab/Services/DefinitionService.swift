import Foundation
// FoundationModels itself needs iOS 26+, well above this project's 18.0
// deployment target (see project.yml), so every symbol that touches it is
// individually `@available`-gated rather than raising the whole app's
// floor — mirrors how `TranslationSession.Configuration` (iOS 18+) already
// sits above `LanguageAvailability` (iOS 17.4+) in `TranslationService`.
import FoundationModels

/// Coarser than `TranslationFieldState`: Apple Intelligence eligibility is a
/// per-device gate (chip, Settings toggle, model download), not a
/// per-language-pair one, so there's no `unsupported(source:target:)`
/// equivalent — just whether the on-device model is available at all.
enum DefinitionAvailability: Equatable {
    case checking
    case available
    case unavailable
}

/// Same-language "explain this word" lookup, distinct from
/// `TranslationService`: a translation maps target language → native
/// language, but a definition stays in the term's own language (e.g. an
/// English word's English definition) — something `TranslationSession` has
/// no way to produce (`source == target` isn't a translation). Backed by
/// Apple's on-device FoundationModels LLM (iOS 26+) rather than the
/// Translation framework's fixed bilingual dictionaries.
@available(iOS 26.0, *)
enum DefinitionService {
    static func checkAvailability() -> DefinitionAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    /// Returns a short, same-language definition of `term`, or `nil` on any
    /// failure — best-effort, per the same silent-failure convention as
    /// `TranslationService`/`TatoebaService`: this is a suggestion the user
    /// can always type manually, never a dependency.
    static func fetchDefinition(term: String, language: String) async -> String? {
        guard !term.isEmpty, case .available = SystemLanguageModel.default.availability else { return nil }

        // The prompt is read by the model, not resolved like
        // `TranslationSession`'s `Locale.Language` — it needs a name a
        // human (and the model) would recognize, not a bare BCP-47 code.
        let languageName = Locale.current.localizedString(forLanguageCode: language) ?? language

        let session = LanguageModelSession(
            instructions: """
            You are a concise monolingual dictionary for \(languageName). Given a \
            word or short phrase in \(languageName), reply with exactly one short, \
            plain-language definition written in \(languageName) itself. Never \
            translate it into another language. No examples, no extra commentary,
            no restating the term.
            """
        )
        do {
            let response = try await session.respond(to: term)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
