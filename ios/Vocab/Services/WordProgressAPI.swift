import Foundation
import Supabase

/// Wrapper over `word_progress`. Unlike `WordAPI`, there is deliberately no
/// `insert`/`delete` here: row *creation* is entirely server-side (a
/// trigger seeds the `recognize` row on word insert, another creates the
/// `recall` row when `recognize` first reaches `learnt` — see the
/// `word_progress` migrations). `update` does exist, for the one client
/// write path that isn't the `record_review` RPC: a manual status override
/// from Word Detail (`WordStore.setStatus`). Both write paths land on the
/// same table, which is exactly what lets the DB-side unlock trigger fire
/// identically regardless of which one moved a word to `learnt`.
enum WordProgressAPI {
    private static var table: PostgrestQueryBuilder {
        SupabaseClientProvider.shared.from("word_progress")
    }

    static func fetchAll() async throws -> [WordProgress] {
        try await table.select().execute().value
    }

    /// Sends only the mutable scheduling fields, never `progress.id` itself.
    /// `id` is server-assigned and the client only learns the real value
    /// once a fetch/Realtime event reconciles it (see `WordProgress`'s doc
    /// comment) — an optimistic local row can carry a client-fabricated
    /// placeholder `id` in the meantime. `PostgrestQueryBuilder.update`
    /// PATCHes the *entire* encoded body regardless of the `.eq()` filters
    /// used to target the row, so encoding the whole `WordProgress` here
    /// would silently overwrite the real row's primary key with that
    /// placeholder. `updatedAt` is omitted too — the `word_progress_set_updated_at`
    /// trigger owns it unconditionally on every UPDATE.
    private struct MutableFields: Encodable {
        let status: WordStatus
        let knowCount: Int
        let intervalStep: Int
        let dueAt: Date?
        let timesSeen: Int
    }

    static func update(_ progress: WordProgress) async throws {
        let body = MutableFields(
            status: progress.status,
            knowCount: progress.knowCount,
            intervalStep: progress.intervalStep,
            dueAt: progress.dueAt,
            timesSeen: progress.timesSeen
        )
        try await table.update(body).eq("word_id", value: progress.wordId).eq("direction", value: progress.direction.rawValue).execute()
    }
}
