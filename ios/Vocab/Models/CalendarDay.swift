import Foundation

/// A calendar day identified purely by year/month/day — deliberately not a
/// `Date` (an instant). Streak bugs almost always come from comparing
/// instants across a timezone/DST boundary instead of comparing calendar
/// days; this type makes that class of bug structurally impossible since
/// there's no instant to compare, only y/m/d.
struct CalendarDay: Codable, Equatable, Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Derives the calendar day for `date` in `timeZone` (default: device's
    /// current timezone). Callers doing streak math should pass an explicit
    /// `Calendar`/`TimeZone` rather than relying on the default, so tests can
    /// simulate other zones/DST boundaries deterministically.
    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let date = calendar.date(from: components) ?? Date()
        let shifted = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return CalendarDay(date: shifted, calendar: calendar)
    }
}
