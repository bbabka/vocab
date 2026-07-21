import XCTest
@testable import Vocab

final class StreakCalculatorTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func activity(_ days: [CalendarDay]) -> [DailyActivity] {
        days.map { DailyActivity(activityDate: $0, reviewsCount: 1) }
    }

    func testCurrentStreakCountsConsecutiveDaysEndingToday() {
        let today = day(2026, 7, 21)
        let history = activity([day(2026, 7, 19), day(2026, 7, 20), today])

        XCTAssertEqual(StreakCalculator.currentStreak(activity: history, today: today), 3)
    }

    func testCurrentStreakCountsFromYesterdayWhenTodayHasNoActivityYet() {
        let today = day(2026, 7, 21)
        let history = activity([day(2026, 7, 19), day(2026, 7, 20)])

        XCTAssertEqual(
            StreakCalculator.currentStreak(activity: history, today: today), 2,
            "a day not yet practiced shouldn't break the streak until it's actually missed"
        )
    }

    func testCurrentStreakIsZeroWhenNeitherTodayNorYesterdayHasActivity() {
        let today = day(2026, 7, 21)
        let history = activity([day(2026, 7, 18)])

        XCTAssertEqual(StreakCalculator.currentStreak(activity: history, today: today), 0)
    }

    func testCurrentStreakBreaksOnAGap() {
        let today = day(2026, 7, 21)
        let history = activity([day(2026, 7, 10), today])

        XCTAssertEqual(StreakCalculator.currentStreak(activity: history, today: today), 1)
    }

    func testLongestStreakFindsBestRunAcrossHistoryNotJustCurrent() {
        // A 4-day run in the past, then a gap, then a 1-day run "today".
        let history = activity([
            day(2026, 7, 1), day(2026, 7, 2), day(2026, 7, 3), day(2026, 7, 4),
            day(2026, 7, 21),
        ])

        XCTAssertEqual(StreakCalculator.longestStreak(activity: history), 4)
    }

    func testDuplicateActivityRowsForSameDayDoNotDoubleCount() {
        let history = activity([day(2026, 7, 20), day(2026, 7, 20), day(2026, 7, 21)])

        XCTAssertEqual(StreakCalculator.longestStreak(activity: history), 2)
    }

    /// DST/month-boundary sanity check: `CalendarDay` carries no instant, so
    /// there's no "spring forward" hour to lose — Nov 1 following Oct 31 is
    /// just two adjacent calendar days regardless of any DST transition that
    /// instant-based date math could otherwise mishandle.
    func testConsecutiveDaysAcrossMonthAndDSTBoundaryStillCountAsAdjacent() {
        let today = day(2026, 11, 1)
        let history = activity([day(2026, 10, 31), today])

        XCTAssertEqual(StreakCalculator.currentStreak(activity: history, today: today), 2)
    }

    func testCalendarDayJustBeforeMidnightIsDistinctFromNextDay() {
        var component = DateComponents()
        component.year = 2026
        component.month = 7
        component.day = 21
        component.hour = 23
        component.minute = 59
        let calendar = Calendar(identifier: .gregorian)
        let lateNight = calendar.date(from: component)!

        XCTAssertEqual(CalendarDay(date: lateNight, calendar: calendar), day(2026, 7, 21))
        XCTAssertNotEqual(
            CalendarDay(date: lateNight, calendar: calendar),
            day(2026, 7, 22),
            "a swipe at 23:59 must count for that calendar day, not spill into the next"
        )
    }
}
