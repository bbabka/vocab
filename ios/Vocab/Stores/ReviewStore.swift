import Foundation
import Supabase

@MainActor
final class ReviewStore: ObservableObject {
    @Published private(set) var reviewLog: [ReviewLogEntry]
    @Published private(set) var dailyActivity: [DailyActivity]
    @Published var syncError: String?

    private let client: SupabaseClient
    private let database: AppDatabase

    init(
        reviewLog: [ReviewLogEntry] = [],
        dailyActivity: [DailyActivity] = MockData.dailyActivity,
        client: SupabaseClient = SupabaseClientProvider.shared,
        database: AppDatabase = .shared
    ) {
        self.reviewLog = reviewLog
        self.dailyActivity = dailyActivity
        self.client = client
        self.database = database
    }

    /// Replaces local state with the signed-in user's rows; RLS scopes the
    /// fetch automatically. `reviewLog` has no local mirror (write-mostly,
    /// online-only per the brief) so a failed fetch just leaves it as-is.
    /// `dailyActivity` does have a mirror: on success it reconciles against
    /// any not-yet-synced outbox rows (taking the max count for a day with a
    /// pending swipe, so a fetch racing the drain can't show a count lower
    /// than what the user already saw locally) and re-mirrors; on failure it
    /// falls back to the mirror outright.
    func loadFromRemote() async {
        syncError = nil
        async let logFetch = ReviewLogAPI.fetchAll()
        async let activityFetch = DailyActivityAPI.fetchAll()
        do {
            let remoteActivity = try await activityFetch
            let pendingDates = Set((try? database.fetchPendingReviews().map(\.activityDate)) ?? [])
            dailyActivity = Self.reconcile(remote: remoteActivity, local: dailyActivity, pendingDates: pendingDates)
            try? database.replaceDailyActivity(dailyActivity)
        } catch {
            if let cached = try? database.fetchDailyActivity() {
                dailyActivity = cached
            }
            appendSyncError(error.localizedDescription)
        }

        do {
            reviewLog = try await logFetch
        } catch {
            appendSyncError(error.localizedDescription)
        }
    }

    /// Accumulates rather than overwrites: `loadFromRemote()` runs two
    /// independent fetches, and if both fail (the realistic fully-offline
    /// case), the second error must not silently erase the first one.
    private func appendSyncError(_ message: String) {
        syncError = [syncError, message].compactMap { $0 }.joined(separator: "; ")
    }

    /// For a day with a pending (not-yet-synced) swipe, the local count is
    /// at least as current as the server's, so keep whichever is higher
    /// rather than risk a fetch that raced the outbox drain regressing what
    /// the user already saw. For any other day, the server is the source of
    /// truth.
    static func reconcile(remote: [DailyActivity], local: [DailyActivity], pendingDates: Set<CalendarDay>) -> [DailyActivity] {
        Reconciler.merge(remote: remote, local: local, key: \.activityDate, pendingKeys: pendingDates) { local, remote, isPending in
            guard isPending else { return remote }
            return DailyActivity(activityDate: remote.activityDate, reviewsCount: max(remote.reviewsCount, local.reviewsCount))
        }
    }

    /// Records the outcome of one swipe: appends the log row in-memory and
    /// bumps (or creates) today's `daily_activity` row, mirroring the
    /// activity bump into GRDB. Deliberately does not talk to the network —
    /// that's `WordStore.applySwipe`'s job now, via the outbox — this just
    /// keeps local state (in-memory and mirrored) consistent with whatever
    /// `WordStore` already queued.
    /// Clears in-memory state on sign-out (see `CollectionStore.reset()` for
    /// why this matters).
    func reset() {
        reviewLog = []
        dailyActivity = []
        syncError = nil
    }

    func record(_ outcome: ReviewScheduler.Outcome) {
        reviewLog.append(outcome.log)

        let updatedActivity: DailyActivity
        if let index = dailyActivity.firstIndex(where: { $0.activityDate == outcome.activityDate }) {
            dailyActivity[index].reviewsCount += 1
            updatedActivity = dailyActivity[index]
        } else {
            updatedActivity = DailyActivity(activityDate: outcome.activityDate, reviewsCount: 1)
            dailyActivity.append(updatedActivity)
        }
        try? database.upsertDailyActivity(updatedActivity)
    }

    func currentStreak(today: CalendarDay = CalendarDay(date: Date())) -> Int {
        StreakCalculator.currentStreak(activity: dailyActivity, today: today)
    }

    func longestStreak() -> Int {
        StreakCalculator.longestStreak(activity: dailyActivity)
    }
}
