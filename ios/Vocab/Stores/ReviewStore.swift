import Foundation
import Supabase

@MainActor
final class ReviewStore: ObservableObject {
    @Published private(set) var reviewLog: [ReviewLogEntry]
    @Published private(set) var dailyActivity: [DailyActivity]
    @Published var syncError: String?

    private let client: SupabaseClient

    init(
        reviewLog: [ReviewLogEntry] = [],
        dailyActivity: [DailyActivity] = MockData.dailyActivity,
        client: SupabaseClient = SupabaseClientProvider.shared
    ) {
        self.reviewLog = reviewLog
        self.dailyActivity = dailyActivity
        self.client = client
    }

    /// Replaces local state with the signed-in user's rows; RLS scopes the
    /// fetch automatically.
    func loadFromRemote() async {
        do {
            async let log = ReviewLogAPI.fetchAll()
            async let activity = DailyActivityAPI.fetchAll()
            (reviewLog, dailyActivity) = try await (log, activity)
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Records the outcome of one swipe: appends the log row and bumps (or
    /// creates) today's `daily_activity` row for `activityDate`, then
    /// persists both in the background (review_log insert, daily_activity
    /// upsert), fire-and-forget — matching `WordStore.applySwipe`'s "instant
    /// locally, sync in the background" contract. Not atomic yet: a failure
    /// partway through can leave the log row written without the activity
    /// bump (or vice versa); the durable, atomic path is Phase 4's RPC.
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

        Task {
            do {
                try await ReviewLogAPI.insert(outcome.log)
                try await DailyActivityAPI.upsert(updatedActivity)
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func currentStreak(today: CalendarDay = CalendarDay(date: Date())) -> Int {
        StreakCalculator.currentStreak(activity: dailyActivity, today: today)
    }

    func longestStreak() -> Int {
        StreakCalculator.longestStreak(activity: dailyActivity)
    }
}
