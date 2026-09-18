import Foundation

/// Tatoeba has no stable, documented official API — only a flaky,
/// rate-limited community endpoint. Treated purely as "might work": a
/// generous timeout, and every failure (network, decode, no results, or an
/// unmapped language) collapses into `nil` rather than surfacing to the
/// caller. If reliable example-fetching is ever needed, the honest fix is
/// importing Tatoeba's downloadable sentence-pair dumps into our own table,
/// not calling this endpoint live.
enum TatoebaService {
    /// Tatoeba's endpoint expects ISO 639-3 codes; `Locale.LanguageCode`
    /// derives the ISO 639-2/T equivalent for any ISO 639-1 code Foundation
    /// knows (iOS 16+), which coincides with ISO 639-3 for the vast
    /// majority of languages. This replaces a hand-maintained ~18-language
    /// map that silently dropped every language outside it (Danish
    /// included) — the same trap `Language.swift`'s pick-list was pulled
    /// out of; see its own doc comment. Chinese is the one language Tatoeba
    /// needs an override for: it expects `"cmn"` (Mandarin), not `"zho"`,
    /// the macrolanguage code Foundation derives for `"zh"`.
    static let iso639_3Overrides: [String: String] = ["zh": "cmn"]

    static func iso639_3(for languageCode: String) -> String? {
        if let override = iso639_3Overrides[languageCode] { return override }
        return Locale.LanguageCode(languageCode).identifier(.alpha3)
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// Best-effort fetch of an example sentence containing `term`, in the
    /// language identified by `languageCode` (ISO 639-1). Returns `nil` on
    /// any failure — never throws, so the caller can treat "no example
    /// found" and "the request failed" identically.
    static func fetchExample(term: String, languageCode: String, nativeLanguageCode: String) async -> String? {
        guard let from = iso639_3(for: languageCode) else { return nil }
        guard var components = URLComponents(string: "https://tatoeba.org/eng/api_v0/search") else { return nil }

        var queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "orphans", value: "no"),
            URLQueryItem(name: "unapproved", value: "no"),
        ]
        if let to = iso639_3(for: nativeLanguageCode) {
            queryItems.append(URLQueryItem(name: "to", value: to))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(TatoebaSearchResponse.self, from: data)
            return decoded.results.first(where: { $0.text.localizedCaseInsensitiveContains(term) })?.text
                ?? decoded.results.first?.text
        } catch {
            return nil
        }
    }
}

private struct TatoebaSearchResponse: Decodable {
    let results: [TatoebaSentence]
}

private struct TatoebaSentence: Decodable {
    let text: String
}
