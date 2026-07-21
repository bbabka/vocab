import XCTest
import Supabase
@testable import Vocab

/// Exercises `WordStore.drainOutbox()` against an in-memory GRDB database
/// and a fake network spy — the "pending_reviews outbox" row from the
/// plan's testing-strategy table: enqueue/drain ordering, idempotent
/// double-drain, and simulated partial-failure-then-retry.
@MainActor
final class OutboxDrainTests: XCTestCase {
    private func makeOutcome(wordId: UUID = UUID(), reviewedAt: Date, activityDate: CalendarDay) -> ReviewScheduler.Outcome {
        let word = Word(id: wordId, collectionId: UUID(), term: "t", translation: "t")
        let log = ReviewLogEntry(
            wordId: wordId, result: .know, phase: .active,
            statusBefore: .new, statusAfter: .learning, reviewedAt: reviewedAt
        )
        return ReviewScheduler.Outcome(word: word, log: log, activityDate: activityDate)
    }

    func testDrainReplaysQueuedReviewsInClientReviewedAtOrderAndEmptiesTheOutbox() async {
        let database = AppDatabase.makeInMemory()
        let spy = ReviewSyncingSpy()
        let store = WordStore(words: [], database: database, reviewSyncing: spy)

        let earlier = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 1_000), activityDate: CalendarDay(date: Date())))
        let later = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 2_000), activityDate: CalendarDay(date: Date())))
        // Enqueue out of order to prove drain sorts by clientReviewedAt, not insertion order.
        try! database.enqueuePendingReview(later)
        try! database.enqueuePendingReview(earlier)

        await store.drainOutbox()

        XCTAssertEqual(spy.recordedIDs, [earlier.id, later.id])
        XCTAssertEqual(try! database.fetchPendingReviews().count, 0)
    }

    func testDoubleDrainIsIdempotentAndDoesNotReplayAlreadySyncedRows() async {
        let database = AppDatabase.makeInMemory()
        let spy = ReviewSyncingSpy()
        let store = WordStore(words: [], database: database, reviewSyncing: spy)
        let review = PendingReview(outcome: makeOutcome(reviewedAt: Date(), activityDate: CalendarDay(date: Date())))
        try! database.enqueuePendingReview(review)

        await store.drainOutbox()
        await store.drainOutbox()

        XCTAssertEqual(spy.recordedIDs, [review.id], "the second drain should find nothing left to replay")
    }

    func testFailedRowHaltsTheDrainWithoutSkippingAheadThenRetriesCleanlyOnceFixed() async {
        let database = AppDatabase.makeInMemory()
        let spy = ReviewSyncingSpy()
        let store = WordStore(words: [], database: database, reviewSyncing: spy)

        let first = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 1_000), activityDate: CalendarDay(date: Date())))
        let second = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 2_000), activityDate: CalendarDay(date: Date())))
        try! database.enqueuePendingReview(first)
        try! database.enqueuePendingReview(second)

        spy.failingIDs = [first.id]
        await store.drainOutbox()

        XCTAssertEqual(spy.attemptedIDs, [first.id], "the drain must halt at the failing row, never skip ahead to the second")
        let stillPending = try! database.fetchPendingReviews()
        XCTAssertEqual(stillPending.map(\.id), [first.id, second.id], "both rows remain queued — the failure didn't drop anything")
        XCTAssertEqual(stillPending.first?.syncStatus, .failed)
        XCTAssertEqual(stillPending.first?.attemptCount, 1)

        spy.failingIDs = []
        spy.recordedIDs = []
        await store.drainOutbox()

        XCTAssertEqual(spy.recordedIDs, [first.id, second.id], "retrying after the fix replays in the original order")
        XCTAssertEqual(try! database.fetchPendingReviews().count, 0)
    }

    // MARK: - Permanent ("word not found") failures are dropped, not halted on

    func testWordNotFoundErrorDropsThatRowAndContinuesDrainingTheRest() async {
        let database = AppDatabase.makeInMemory()
        let spy = ReviewSyncingSpy()
        let store = WordStore(words: [], database: database, reviewSyncing: spy)

        let deletedWordReview = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 1_000), activityDate: CalendarDay(date: Date())))
        let healthyReview = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 2_000), activityDate: CalendarDay(date: Date())))
        try! database.enqueuePendingReview(deletedWordReview)
        try! database.enqueuePendingReview(healthyReview)

        spy.wordNotFoundIDs = [deletedWordReview.id]
        await store.drainOutbox()

        XCTAssertEqual(
            spy.recordedIDs, [healthyReview.id],
            "a permanent 'word not found' failure must not halt the drain the way a transient failure does"
        )
        XCTAssertTrue(try! database.fetchPendingReviews().isEmpty, "the unrecoverable row should be dropped, not left queued forever")
    }

    // MARK: - A swipe enqueued mid-drain is picked up by the same drain, not stranded

    func testReviewEnqueuedWhileADrainIsInFlightIsPickedUpBeforeThatDrainReturns() async {
        let database = AppDatabase.makeInMemory()
        let store = WordStore(words: [], database: database, reviewSyncing: MidDrainEnqueuingSyncing(database: database))
        let first = PendingReview(outcome: makeOutcome(reviewedAt: Date(timeIntervalSince1970: 1_000), activityDate: CalendarDay(date: Date())))
        try! database.enqueuePendingReview(first)

        await store.drainOutbox()

        XCTAssertTrue(
            try! database.fetchPendingReviews().isEmpty,
            "a row enqueued while this drain was awaiting the first row's network call should still be drained in the same call, not stranded until some later trigger"
        )
    }
}

/// Simulates the real race from the review: while "syncing" the first row,
/// a second row gets enqueued directly into the same database — as if
/// another `applySwipe` call landed while this drain's network call was in
/// flight. Succeeds unconditionally so the test isolates the snapshot/race
/// behavior from any failure handling.
private final class MidDrainEnqueuingSyncing: ReviewSyncing, @unchecked Sendable {
    private let database: AppDatabase
    private var hasEnqueuedSecondRow = false

    init(database: AppDatabase) {
        self.database = database
    }

    func recordReview(_ review: PendingReview) async throws {
        if !hasEnqueuedSecondRow {
            hasEnqueuedSecondRow = true
            let second = PendingReview(outcome: ReviewScheduler.Outcome(
                word: Word(collectionId: UUID(), term: "t2", translation: "t2"),
                log: ReviewLogEntry(wordId: UUID(), result: .know, phase: .active, statusBefore: .new, statusAfter: .learning, reviewedAt: Date(timeIntervalSince1970: 2_000)),
                activityDate: CalendarDay(date: Date())
            ))
            try? database.enqueuePendingReview(second)
        }
    }
}

/// Records every id it's asked to sync, in call order, and can be told to
/// fail specific ids on demand — the "fake API spy" the plan's testing
/// strategy calls for.
private final class ReviewSyncingSpy: ReviewSyncing, @unchecked Sendable {
    struct Failure: Error {}

    /// Every id `recordReview` was called with, success or failure — lets a
    /// test prove the drain reached (and stopped at) a specific row.
    var attemptedIDs: [UUID] = []
    /// Ids that actually succeeded.
    var recordedIDs: [UUID] = []
    var failingIDs: Set<UUID> = []
    /// Ids to fail with the same `PostgrestError` code `record_review`
    /// raises for "word not found or not owned" — simulates the permanent,
    /// drop-don't-halt case rather than a transient `Failure()`.
    var wordNotFoundIDs: Set<UUID> = []

    func recordReview(_ review: PendingReview) async throws {
        attemptedIDs.append(review.id)
        if wordNotFoundIDs.contains(review.id) {
            throw PostgrestError(code: "VC001", message: "record_review: word not found or not owned by caller")
        }
        if failingIDs.contains(review.id) {
            throw Failure()
        }
        recordedIDs.append(review.id)
    }
}
