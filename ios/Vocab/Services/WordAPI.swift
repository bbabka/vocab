import Foundation
import Supabase

/// Thin wrapper over `words`. The model already maps 1:1 to the table's
/// columns (minus server-defaulted `user_id`), so it doubles as its own
/// encode/decode "row" type — no separate DTO needed.
enum WordAPI {
    private static var table: PostgrestQueryBuilder {
        SupabaseClientProvider.shared.from("words")
    }

    static func fetchAll() async throws -> [Word] {
        try await table.select().order("created_at", ascending: true).execute().value
    }

    static func insert(_ word: Word) async throws {
        try await table.insert(word).execute()
    }

    static func update(_ word: Word) async throws {
        try await table.update(word).eq("id", value: word.id).execute()
    }

    static func delete(_ id: UUID) async throws {
        try await table.delete().eq("id", value: id).execute()
    }
}
