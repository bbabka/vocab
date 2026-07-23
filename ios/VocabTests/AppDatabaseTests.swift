import XCTest
@testable import Vocab

/// Round-trip fidelity for the GRDB local mirrors — this is new storage
/// surface (UUID-as-blob primary keys, `CalendarDay`'s custom
/// `DatabaseValueConvertible`, optional `Date` columns), so it's worth its
/// own coverage independent of the store-level tests.
final class AppDatabaseTests: XCTestCase {
    // GRDB's default SQLite `Date` storage is millisecond-precision text, but
    // `Date()` carries sub-millisecond precision — fine for a read cache (the
    // source of truth stays Postgres) but it means exact-equality round-trip
    // assertions need a fixture `Date` that's already millisecond-aligned,
    // same convention `ReviewSchedulerTests` already uses for determinism.
    private static let fixedInstant = Date(timeIntervalSince1970: 1_700_000_000)

    func testWordRoundTripsThroughLocalMirrorIncludingOptionalFields() throws {
        let database = AppDatabase.makeInMemory()
        let word = Word(
            collectionId: UUID(),
            term: "Wort",
            // Multiple meanings, each with its own part of speech — this is
            // the actual new surface here: GRDB's Codable-derived record
            // conformance must JSON-round-trip the whole array, not just a
            // single scalar column.
            meanings: [
                WordMeaning(translation: "word", partOfSpeech: .noun),
                WordMeaning(translation: "to word (something)", partOfSpeech: .verb),
            ],
            pronunciation: "vɔʁt",
            exampleSentence: "Ein Wort.",
            status: .learnt,
            importance: 3,
            knowCount: 3,
            intervalStep: 1,
            dueAt: Date(timeIntervalSince1970: 1_700_000_000),
            timesSeen: 7,
            createdAt: Self.fixedInstant,
            updatedAt: Self.fixedInstant
        )

        try database.replaceWords([word])
        let fetched = try database.fetchWords()

        XCTAssertEqual(fetched, [word])
    }

    func testWordWithNilOptionalFieldsRoundTrips() throws {
        let database = AppDatabase.makeInMemory()
        let word = Word(
            collectionId: UUID(), term: "hi", translation: "hi", pronunciation: nil, exampleSentence: nil, dueAt: nil,
            createdAt: Self.fixedInstant, updatedAt: Self.fixedInstant
        )

        try database.replaceWords([word])

        XCTAssertEqual(try database.fetchWords(), [word])
    }

    func testCollectionRoundTripsThroughLocalMirror() throws {
        let database = AppDatabase.makeInMemory()
        let collection = WordCollection(
            name: "Danish — Basics", targetLanguage: "da", nativeLanguage: "en", createdAt: Self.fixedInstant
        )

        try database.replaceCollections([collection])

        XCTAssertEqual(try database.fetchCollections(), [collection])
    }

    func testDailyActivityRoundTripsThroughLocalMirror() throws {
        let database = AppDatabase.makeInMemory()
        let activity = DailyActivity(activityDate: CalendarDay(year: 2026, month: 7, day: 21), reviewsCount: 4)

        try database.replaceDailyActivity([activity])

        XCTAssertEqual(try database.fetchDailyActivity(), [activity])
    }

    func testUpsertWordUpdatesExistingRowRatherThanDuplicating() throws {
        let database = AppDatabase.makeInMemory()
        var word = Word(collectionId: UUID(), term: "t", translation: "t")
        try database.upsertWord(word)

        word.knowCount = 2
        try database.upsertWord(word)

        let fetched = try database.fetchWords()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.knowCount, 2)
    }

    func testDeleteWordsForCollectionIdCascadesTheLocalMirror() throws {
        let database = AppDatabase.makeInMemory()
        let collectionId = UUID()
        let otherCollectionId = UUID()
        let wordInCollection = Word(collectionId: collectionId, term: "a", translation: "a")
        let wordInOtherCollection = Word(collectionId: otherCollectionId, term: "b", translation: "b")
        try database.replaceWords([wordInCollection, wordInOtherCollection])

        try database.deleteWords(forCollectionId: collectionId)

        XCTAssertEqual(try database.fetchWords().map(\.id), [wordInOtherCollection.id])
    }

    func testDeletePendingReviewsForWordIdRemovesOnlyThatWordsQueuedReviews() throws {
        let database = AppDatabase.makeInMemory()
        let targetWordId = UUID()
        let otherWordId = UUID()

        func makeReview(wordId: UUID) -> PendingReview {
            let word = Word(id: wordId, collectionId: UUID(), term: "t", translation: "t")
            let log = ReviewLogEntry(wordId: wordId, result: .know, phase: .active, statusBefore: .new, statusAfter: .learning)
            return PendingReview(outcome: ReviewScheduler.Outcome(word: word, log: log, activityDate: CalendarDay(date: Date())))
        }
        let targetReview = makeReview(wordId: targetWordId)
        let otherReview = makeReview(wordId: otherWordId)
        try database.enqueuePendingReview(targetReview)
        try database.enqueuePendingReview(otherReview)

        try database.deletePendingReviews(forWordId: targetWordId)

        XCTAssertEqual(try database.fetchPendingReviews().map(\.id), [otherReview.id])
    }

    func testWipeClearsAllLocalTables() throws {
        let database = AppDatabase.makeInMemory()
        let word = Word(collectionId: UUID(), term: "t", translation: "t")
        let collection = WordCollection(name: "n", targetLanguage: "es", nativeLanguage: "en")
        let activity = DailyActivity(activityDate: CalendarDay(date: Date()), reviewsCount: 1)
        try database.replaceWords([word])
        try database.replaceCollections([collection])
        try database.replaceDailyActivity([activity])
        let outcome = ReviewScheduler.Outcome(
            word: word,
            log: ReviewLogEntry(wordId: word.id, result: .know, phase: .active, statusBefore: .new, statusAfter: .learning),
            activityDate: activity.activityDate
        )
        try database.enqueuePendingReview(PendingReview(outcome: outcome))

        try database.wipe()

        XCTAssertTrue(try database.fetchWords().isEmpty)
        XCTAssertTrue(try database.fetchCollections().isEmpty)
        XCTAssertTrue(try database.fetchDailyActivity().isEmpty)
        XCTAssertTrue(try database.fetchPendingReviews().isEmpty)
    }
}
