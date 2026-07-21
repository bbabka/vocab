import Foundation

/// Computes streaks from a set of active days. Pure and clock-injected:
/// callers pass `today` explicitly (derived from `CalendarDay(date:calendar:)`
/// at the call site) rather than this type reaching for `Date()`/
/// `TimeZone.current` itself, so DST- and midnight-boundary behavior is
/// deterministic and testable rather than dependent on when the test runs.
enum StreakCalculator {
    /// Consecutive days with activity, counting back from `today` if `today`
    /// itself has activity, otherwise from `today - 1` (a day not yet
    /// practiced doesn't break the streak until it's actually missed).
    static func currentStreak(activity: [DailyActivity], today: CalendarDay) -> Int {
        let activeDays = Set(activity.map(\.activityDate))

        var cursor = activeDays.contains(today) ? today : today.adding(days: -1)
        guard activeDays.contains(cursor) else { return 0 }

        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            cursor = cursor.adding(days: -1)
        }
        return streak
    }

    /// Longest run of consecutive active days across all recorded history.
    static func longestStreak(activity: [DailyActivity]) -> Int {
        let sortedDays = activity.map(\.activityDate).sorted()
        guard var previous = sortedDays.first else { return 0 }

        var longest = 1
        var current = 1
        for day in sortedDays.dropFirst() {
            if day == previous {
                continue // same day appearing twice shouldn't double-count
            }
            if day == previous.adding(days: 1) {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }
}
