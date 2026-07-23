import Foundation

/// One cell in the Stats heatmap grid. `nil` in the grid (not this type)
/// represents a day that hasn't happened yet — a real day with zero
/// reviews is still a `HeatmapCell` with `reviewsCount == 0`.
struct HeatmapCell: Equatable {
    let day: CalendarDay
    let reviewsCount: Int
}

/// Builds the GitHub-style contribution grid for `StatsView`. Pure and
/// clock-injected like `StreakCalculator` — calendar-boundary code is easy
/// to get subtly wrong, so this stays independent of `Date()`/
/// `Calendar.current` to keep it deterministically testable.
enum HeatmapBuilder {
    /// Returns `weeks` columns of exactly 7 rows each (row 0 = Sunday ...
    /// row 6 = Saturday), with the rightmost column ending on `today`'s
    /// calendar week. Days after `today` (the remainder of its own week)
    /// are `nil` rather than omitted, so every column is a full week and
    /// the grid stays a clean rectangle regardless of which weekday
    /// `today` happens to be.
    static func grid(
        activity: [DailyActivity],
        weeks: Int,
        today: CalendarDay,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [[HeatmapCell?]] {
        let countsByDay = Dictionary(uniqueKeysWithValues: activity.map { ($0.activityDate, $0.reviewsCount) })

        let todayDate = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day)) ?? Date()
        let weekday = calendar.component(.weekday, from: todayDate) // 1 (Sun) ... 7 (Sat)
        let windowEnd = today.adding(days: 7 - weekday, calendar: calendar)
        let windowStart = windowEnd.adding(days: -(weeks * 7 - 1), calendar: calendar)

        let cells: [HeatmapCell?] = (0..<(weeks * 7)).map { offset in
            let day = windowStart.adding(days: offset, calendar: calendar)
            guard day <= today else { return nil }
            return HeatmapCell(day: day, reviewsCount: countsByDay[day] ?? 0)
        }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}
