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

    private func makeStore(reviewLog: [ReviewLogEntry] = [], dailyActivity: [DailyActivity] = []) -> ReviewStore {
        ReviewStore(reviewLog: reviewLog, dailyActivity: dailyActivity, database: .makeInMemory())
    }

    func testRecordAppendsLogEntry() {
        let store = makeStore()
        let outcome = makeOutcome(activityDate: CalendarDay(date: now))

        store.record(outcome)

        XCTAssertEqual(store.reviewLog, [outcome.log])
    }

    func testRecordCreatesDailyActivityRowWhenNoneExistsForThatDay() {
        let store = makeStore()
        let today = CalendarDay(date: now)

        store.record(makeOutcome(activityDate: today))

        XCTAssertEqual(store.dailyActivity, [DailyActivity(activityDate: today, reviewsCount: 1)])
    }

    func testRecordIncrementsExistingDailyActivityRowForSameDay() {
        let today = CalendarDay(date: now)
        let store = makeStore(dailyActivity: [DailyActivity(activityDate: today, reviewsCount: 4)])

        store.record(makeOutcome(activityDate: today))

        XCTAssertEqual(store.dailyActivity, [DailyActivity(activityDate: today, reviewsCount: 5)])
    }

    func testCurrentStreakDelegatesToStreakCalculator() {
        let today = CalendarDay(date: now)
        let store = makeStore(dailyActivity: [DailyActivity(activityDate: today, reviewsCount: 1)])

        XCTAssertEqual(store.currentStreak(today: today), 1)
    }

    // MARK: - loadFromRemote reconciliation

    func testDailyActivityReconcileTakesMaxCountForPendingDate() {
        let today = CalendarDay(date: now)
        let remote = [DailyActivity(activityDate: today, reviewsCount: 3)]
        let local = [DailyActivity(activityDate: today, reviewsCount: 5)]

        let reconciled = ReviewStore.reconcile(remote: remote, local: local, pendingDates: [today])

        XCTAssertEqual(reconciled, [DailyActivity(activityDate: today, reviewsCount: 5)])
    }

    func testDailyActivityReconcilePrefersRemoteWhenDateHasNoPendingReview() {
        let today = CalendarDay(date: now)
        let remote = [DailyActivity(activityDate: today, reviewsCount: 3)]
        let local = [DailyActivity(activityDate: today, reviewsCount: 5)]

        let reconciled = ReviewStore.reconcile(remote: remote, local: local, pendingDates: [])

        XCTAssertEqual(reconciled, [DailyActivity(activityDate: today, reviewsCount: 3)])
    }

    func testDailyActivityReconcileKeepsLocalOnlyDateWithPendingReview() {
        let today = CalendarDay(date: now)
        let local = [DailyActivity(activityDate: today, reviewsCount: 1)]

        let reconciled = ReviewStore.reconcile(remote: [], local: local, pendingDates: [today])

        XCTAssertEqual(reconciled, local)
    }

    // MARK: - applyRealtimeChange (single-row upsert)

    func testRealtimeUpsertTakesMaxCountForPendingDate() {
        let today = CalendarDay(date: now)
        let local = [DailyActivity(activityDate: today, reviewsCount: 5)]
        let remote = DailyActivity(activityDate: today, reviewsCount: 3)

        let result = ReviewStore.applyingRealtimeUpsert(remote, into: local, pendingDates: [today])

        XCTAssertEqual(result, [DailyActivity(activityDate: today, reviewsCount: 5)])
    }

    func testRealtimeUpsertPrefersRemoteWhenDateHasNoPendingReview() {
        let today = CalendarDay(date: now)
        let local = [DailyActivity(activityDate: today, reviewsCount: 5)]
        let remote = DailyActivity(activityDate: today, reviewsCount: 3)

        let result = ReviewStore.applyingRealtimeUpsert(remote, into: local, pendingDates: [])

        XCTAssertEqual(result, [DailyActivity(activityDate: today, reviewsCount: 3)])
    }

    func testRealtimeUpsertAppendsADayNotYetKnownLocally() {
        let today = CalendarDay(date: now)
        let remote = DailyActivity(activityDate: today, reviewsCount: 2)

        let result = ReviewStore.applyingRealtimeUpsert(remote, into: [], pendingDates: [])

        XCTAssertEqual(result, [remote])
    }
}
