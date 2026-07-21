import XCTest
@testable import Vocab

/// `AuthStore.signOut()`'s guard against discarding an undrained outbox —
/// the actual drain attempt is `SettingsView`'s job (via
/// `WordStore.drainOutbox()`), so this only needs to verify the guard
/// itself: given pending reviews already queued, does sign-out refuse
/// rather than wipe them?
@MainActor
final class AuthStoreTests: XCTestCase {
    private func makeReview() -> PendingReview {
        let word = Word(collectionId: UUID(), term: "t", translation: "t")
        let log = ReviewLogEntry(wordId: word.id, result: .know, phase: .active, statusBefore: .new, statusAfter: .learning)
        return PendingReview(outcome: ReviewScheduler.Outcome(word: word, log: log, activityDate: CalendarDay(date: Date())))
    }

    func testSignOutRefusesAndSetsAnErrorWhenTheOutboxHasUnsyncedReviews() async throws {
        let database = AppDatabase.makeInMemory()
        try database.enqueuePendingReview(makeReview())
        let store = AuthStore(database: database)

        await store.signOut()

        XCTAssertNotNil(store.errorMessage, "signing out with unsynced reviews queued must surface an error, not silently proceed")
        XCTAssertFalse(try database.fetchPendingReviews().isEmpty, "the outbox must not be wiped while sign-out is refused")
    }

    func testSignOutProceedsWithNoErrorWhenTheOutboxIsEmpty() async throws {
        let database = AppDatabase.makeInMemory()
        let store = AuthStore(database: database)

        await store.signOut()

        XCTAssertNil(store.errorMessage)
    }
}
