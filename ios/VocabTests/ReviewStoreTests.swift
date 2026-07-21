import XCTest
@testable import Vocab

@MainActor
final class ReviewStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeOutcome(activityDate: CalendarDay) -> ReviewScheduler.Outcome {
        let word = Word(collectionId: UUID(), term: "t", translation: "t")
        let log = ReviewLogEntry(wordId: word.id, result: .know, phase: .active, statusBefore: .new, statusAfter: .learning, reviewedAt: now)
        return ReviewScheduler.Outcome(word: word, log: log, activityDate: activityDate)
    }

    func testRecordAppendsLogEntry() {
        let store = ReviewStore(reviewLog: [], dailyActivity: [])
        let outcome = makeOutcome(activityDate: CalendarDay(date: now))

        store.record(outcome)

        XCTAssertEqual(store.reviewLog, [outcome.log])
    }

    func testRecordCreatesDailyActivityRowWhenNoneExistsForThatDay() {
        let store = ReviewStore(reviewLog: [], dailyActivity: [])
        let today = CalendarDay(date: now)

        store.record(makeOutcome(activityDate: today))

        XCTAssertEqual(store.dailyActivity, [DailyActivity(activityDate: today, reviewsCount: 1)])
    }

    func testRecordIncrementsExistingDailyActivityRowForSameDay() {
        let today = CalendarDay(date: now)
        let store = ReviewStore(reviewLog: [], dailyActivity: [DailyActivity(activityDate: today, reviewsCount: 4)])

        store.record(makeOutcome(activityDate: today))

        XCTAssertEqual(store.dailyActivity, [DailyActivity(activityDate: today, reviewsCount: 5)])
    }

    func testCurrentStreakDelegatesToStreakCalculator() {
        let today = CalendarDay(date: now)
        let store = ReviewStore(reviewLog: [], dailyActivity: [DailyActivity(activityDate: today, reviewsCount: 1)])

        XCTAssertEqual(store.currentStreak(today: today), 1)
    }
}
