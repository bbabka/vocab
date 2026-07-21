import Foundation

/// Tatoeba has no stable, documented official API — only a flaky,
/// rate-limited community endpoint. Treated purely as "might work": a
/// generous timeout, and every failure (network, decode, no results, or an
/// unmapped language) collapses into `nil` rather than surfacing to the
/// caller. If reliable example-fetching is ever needed, the honest fix is
/// importing Tatoeba's downloadable sentence-pair dumps into our own table,
/// not calling this endpoint live.
enum TatoebaService {
    /// `Language.common`'s ISO 639-1 codes mapped to the ISO 639-3 codes
    /// Tatoeba's endpoint expects (e.g. `"de"` -> `"deu"`).
    static let iso639_3: [String: String] = [
        "en": "eng", "es": "spa", "fr": "fra", "de": "deu", "it": "ita",
        "pt": "por", "nl": "nld", "sv": "swe", "pl": "pol", "ru": "rus",
        "tr": "tur", "ar": "ara", "hi": "hin", "ja": "jpn", "ko": "kor",
        "zh": "cmn", "vi": "vie", "cs": "ces",
    ]

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
        guard let from = iso639_3[languageCode] else { return nil }
        guard var components = URLComponents(string: "https://tatoeba.org/eng/api_v0/search") else { return nil }

        var queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "orphans", value: "no"),
            URLQueryItem(name: "unapproved", value: "no"),
        ]
        if let to = iso639_3[nativeLanguageCode] {
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
