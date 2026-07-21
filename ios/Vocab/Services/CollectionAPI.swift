import Foundation
import Supabase

/// Thin wrapper over `collections`. The model already maps 1:1 to the
/// table's columns (minus server-defaulted `user_id`), so it doubles as its
/// own encode/decode "row" type — no separate DTO needed.
enum CollectionAPI {
    private static var table: PostgrestQueryBuilder {
        SupabaseClientProvider.shared.from("collections")
    }

    static func fetchAll() async throws -> [WordCollection] {
        try await table.select().order("created_at", ascending: true).execute().value
    }

    static func insert(_ collection: WordCollection) async throws {
        try await table.insert(collection).execute()
    }

    static func update(_ collection: WordCollection) async throws {
        try await table.update(collection).eq("id", value: collection.id).execute()
    }

    static func delete(_ id: UUID) async throws {
        try await table.delete().eq("id", value: id).execute()
    }
}
