import Foundation

/// A curated pick-list for the collection-creation UI. `WordCollection`'s
/// `targetLanguage`/`nativeLanguage` are free BCP-47 strings with no server-
/// side validation (see the brief) — this list is just a convenience picker,
/// not an allowlist.
struct Language: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    static let common: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "it", name: "Italian"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "pl", name: "Polish"),
        Language(code: "ru", name: "Russian"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "vi", name: "Vietnamese"),
        Language(code: "cs", name: "Czech"),
    ]
}
