import Foundation
import Supabase

enum SupabaseClientProvider {
    /// `emitLocalSessionAsInitialSession: true` opts in now to
    /// supabase-swift's post-v2.53 default (see
    /// https://github.com/supabase/supabase-swift/pull/822): the locally
    /// stored session is emitted as `authStateChanges`'s first event right
    /// away, rather than only after a network round trip to refresh it.
    /// `AuthStore.observeAuthState()` deliberately does *not* special-case
    /// an expired initial session — every request already re-validates
    /// its own token via the SDK's per-request refresh, and every fetch in
    /// this app already falls back to the local GRDB mirror on failure (see
    /// `WordStore`/`CollectionStore`/`ReviewStore`'s `loadFromRemote()`), so
    /// a stale cached session degrades the same way an offline launch
    /// already does, rather than needing its own guard.
    static let shared = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(
            db: .init(encoder: postgrestEncoder, decoder: postgrestDecoder),
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )

    /// Models map 1:1 to their table's columns (minus `user_id`, which is
    /// server-defaulted via `auth.uid()` and never sent by the client), using
    /// plain camelCase Swift properties. `convertToSnakeCase`/
    /// `convertFromSnakeCase` do the `collectionId` <-> `collection_id`
    /// translation so no model needs hand-written `CodingKeys`.
    private static var postgrestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Formatter.string(from: date))
        }
        return encoder
    }

    /// Exposed for `RealtimeService` to decode `postgres_changes` row
    /// payloads with the same snake_case/ISO8601 rules PostgREST responses
    /// already use, so a live update and a fetched snapshot decode
    /// identically.
    static var payloadDecoder: JSONDecoder { postgrestDecoder }

    private static var postgrestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601Formatter.date(from: string) ?? iso8601FormatterNoFractional.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(string)"
            )
        }
        return decoder
    }

    /// PostgREST returns `timestamptz` columns with fractional seconds
    /// (e.g. `2026-07-21T14:53:41.091+00:00`); the no-fractional formatter is
    /// a fallback for values that happen to land on a whole second.
    /// `nonisolated(unsafe)`: never mutated after initialization, and
    /// `ISO8601DateFormatter`'s format/parse methods (unlike `DateFormatter`)
    /// are safe to call concurrently.
    private static nonisolated(unsafe) let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static nonisolated(unsafe) let iso8601FormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
