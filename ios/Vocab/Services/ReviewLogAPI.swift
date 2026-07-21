import Foundation
import Supabase

/// Thin wrapper over `review_log`. Append-only: no update/delete needed.
enum ReviewLogAPI {
    private static var table: PostgrestQueryBuilder {
        SupabaseClientProvider.shared.from("review_log")
    }

    static func fetchAll() async throws -> [ReviewLogEntry] {
        try await table.select().order("reviewed_at", ascending: true).execute().value
    }

    static func insert(_ entry: ReviewLogEntry) async throws {
        try await table.insert(entry).execute()
    }
}
