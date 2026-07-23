import XCTest
@testable import Vocab

final class HeatmapBuilderTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    func testGridHasExactlyWeeksColumnsOfSevenRows() {
        let today = day(2026, 7, 22) // a Wednesday
        let grid = HeatmapBuilder.grid(activity: [], weeks: 12, today: today)

        XCTAssertEqual(grid.count, 12)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
    }

    func testTodayLandsInTheLastColumnAtItsOwnWeekdayRow() {
        let today = day(2026, 7, 22) // Wednesday: weekday index 4 (Sun=1...Sat=7) -> row 3
        let grid = HeatmapBuilder.grid(activity: [], weeks: 4, today: today)

        XCTAssertEqual(grid.last?[3]?.day, today)
    }

    func testDaysAfterTodayInItsOwnWeekAreNilNotOmitted() {
        let today = day(2026, 7, 22) // Wednesday: rows 4...6 (Thu/Fri/Sat) haven't happened yet
        let grid = HeatmapBuilder.grid(activity: [], weeks: 4, today: today)

        XCTAssertNil(grid.last?[4])
        XCTAssertNil(grid.last?[5])
        XCTAssertNil(grid.last?[6])
    }

    func testEveryPastDayInTheWindowIsPresentEvenWithZeroReviews() {
        let today = day(2026, 7, 22)
        let grid = HeatmapBuilder.grid(activity: [], weeks: 2, today: today)

        let allCells = grid.flatMap { $0 }
        XCTAssertEqual(allCells.compactMap { $0 }.count, 2 * 7 - 3, "everything except the 3 not-yet-happened days this week")
        XCTAssertTrue(allCells.compactMap { $0 }.allSatisfy { $0.reviewsCount == 0 })
    }

    func testReviewsCountIsLookedUpForTheMatchingDay() {
        let today = day(2026, 7, 22)
        let activity = [DailyActivity(activityDate: today, reviewsCount: 5)]
        let grid = HeatmapBuilder.grid(activity: activity, weeks: 1, today: today)

        XCTAssertEqual(grid.last?[3]?.reviewsCount, 5)
    }

    func testSundayTodayFillsAllSevenRowsInTheLastColumn() {
        let today = day(2026, 7, 26) // a Sunday: row 0, nothing after it this week
        let grid = HeatmapBuilder.grid(activity: [], weeks: 3, today: today)

        XCTAssertEqual(grid.last?.compactMap { $0 }.count, 1, "only today itself; the rest of its week is still ahead")
        XCTAssertEqual(grid.last?[0]?.day, today)
    }

    func testSaturdayTodayFillsAllPriorRowsInTheLastColumn() {
        let today = day(2026, 8, 1) // a Saturday: row 6, the full week has already happened
        let grid = HeatmapBuilder.grid(activity: [], weeks: 3, today: today)

        XCTAssertEqual(grid.last?.compactMap { $0 }.count, 7)
        XCTAssertEqual(grid.last?[6]?.day, today)
    }
}
