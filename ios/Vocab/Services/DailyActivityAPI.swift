import Foundation
import Supabase

/// Thin wrapper over `daily_activity`. Upsert, not atomic increment — Phase 3
/// sends this client's locally-computed `reviewsCount` and merges on
/// conflict; the atomic `reviews_count = reviews_count + 1` RPC lands in
/// Phase 4 alongside the offline outbox.
enum DailyActivityAPI {
    private static var table: PostgrestQueryBuilder {
        SupabaseClientProvider.shared.from("daily_activity")
    }

    static func fetchAll() async throws -> [DailyActivity] {
        try await table.select().order("activity_date", ascending: true).execute().value
    }

    static func upsert(_ activity: DailyActivity) async throws {
        try await table.upsert(activity, onConflict: "user_id,activity_date").execute()
    }
}
