import Foundation

/// A convenience pick-list for the collection-creation UI. `WordCollection`'s
/// `targetLanguage`/`nativeLanguage` are free BCP-47 strings with no server-
/// side validation (see the brief) — this list is not an allowlist, and
/// autotranslate availability is a separate runtime check
/// (`TranslationService.checkAvailability`) that isn't gated by it (e.g.
/// Danish translates fine despite the old hand-picked list omitting it).
/// Built from every ISO 639-1 code Foundation knows a localized name for,
/// rather than hand-maintaining a short list that inevitably falls behind.
struct Language: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    static let common: [Language] = Locale.LanguageCode.isoLanguageCodes
        .filter { $0.identifier.count == 2 }
        .compactMap { code in
            Locale.current.localizedString(forLanguageCode: code.identifier).map { Language(code: code.identifier, name: $0) }
        }
        .sorted { $0.name < $1.name }
}
