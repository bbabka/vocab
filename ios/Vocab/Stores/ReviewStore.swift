import Foundation

@MainActor
final class ReviewStore: ObservableObject {
    @Published private(set) var reviewLog: [ReviewLogEntry]
    @Published private(set) var dailyActivity: [DailyActivity]

    init(
        reviewLog: [ReviewLogEntry] = [],
        dailyActivity: [DailyActivity] = MockData.dailyActivity
    ) {
        self.reviewLog = reviewLog
        self.dailyActivity = dailyActivity
    }

    /// No-op until Phase 3 wires a real Supabase-backed implementation.
    func loadFromRemote() async {}

    /// Records the outcome of one swipe: appends the log row and bumps (or
    /// creates) today's `daily_activity` row for `activityDate`.
    func record(_ outcome: ReviewScheduler.Outcome) {
        reviewLog.append(outcome.log)

        if let index = dailyActivity.firstIndex(where: { $0.activityDate == outcome.activityDate }) {
            dailyActivity[index].reviewsCount += 1
        } else {
            dailyActivity.append(DailyActivity(activityDate: outcome.activityDate, reviewsCount: 1))
        }
    }

    func currentStreak(today: CalendarDay = CalendarDay(date: Date())) -> Int {
        StreakCalculator.currentStreak(activity: dailyActivity, today: today)
    }

    func longestStreak() -> Int {
        StreakCalculator.longestStreak(activity: dailyActivity)
    }
}
