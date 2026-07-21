import Foundation

/// A calendar day identified purely by year/month/day — deliberately not a
/// `Date` (an instant). Streak bugs almost always come from comparing
/// instants across a timezone/DST boundary instead of comparing calendar
/// days; this type makes that class of bug structurally impossible since
/// there's no instant to compare, only y/m/d.
struct CalendarDay: Equatable, Hashable, Comparable, Sendable {
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

/// Wire format for Postgres `date` columns (`daily_activity.activity_date`):
/// a plain `"yyyy-MM-dd"` string, not the `{year,month,day}` object a
/// synthesized `Codable` would produce.
extension CalendarDay: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let parts = string.split(separator: "-")
        guard parts.count == 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(string)"
            )
        }
        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let string = String(format: "%04d-%02d-%02d", year, month, day)
        try container.encode(string)
    }
}
