import XCTest
@testable import Vocab

/// Round-trip fidelity for the GRDB local mirrors — this is new storage
/// surface (UUID-as-blob primary keys, `CalendarDay`'s custom
/// `DatabaseValueConvertible`, optional `Date` columns, and — since Recall
/// Layer (v2) — `local_word_progress`'s composite `(wordId, direction)`
/// primary key), so it's worth its own coverage independent of the
/// store-level tests.
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
            importance: 3,
            recallUnlockedAt: Date(timeIntervalSince1970: 1_700_000_000),
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
            collectionId: UUID(), term: "hi", translation: "hi", pronunciation: nil, exampleSentence: nil, recallUnlockedAt: nil,
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

        word.importance = 3
        try database.upsertWord(word)

        let fetched = try database.fetchWords()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.importance, 3)
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

    // MARK: - local_word_progress (composite (wordId, direction) primary key)

    func testWordProgressRoundTripsThroughLocalMirror() throws {
        let database = AppDatabase.makeInMemory()
        let progress = WordProgress(
            wordId: UUID(), direction: .recall, status: .learning, knowCount: 1, intervalStep: 0,
            dueAt: nil, timesSeen: 2, updatedAt: Self.fixedInstant
        )

        try database.replaceWordProgress([progress])

        XCTAssertEqual(try database.fetchWordProgress(), [progress])
    }

    func testUpsertWordProgressUpdatesExistingRowRatherThanDuplicating() throws {
        let database = AppDatabase.makeInMemory()
        let wordId = UUID()
        var progress = WordProgress(wordId: wordId, direction: .recognize, status: .new)
        try database.upsertWordProgress(progress)

        progress.knowCount = 2
        try database.upsertWordProgress(progress)

        let fetched = try database.fetchWordProgress()
        XCTAssertEqual(fetched.count, 1, "same (wordId, direction) must upsert in place, not duplicate")
        XCTAssertEqual(fetched.first?.knowCount, 2)
    }

    func testUpsertWordProgressKeepsSeparateRowsPerDirectionForTheSameWord() throws {
        let database = AppDatabase.makeInMemory()
        let wordId = UUID()
        try database.upsertWordProgress(WordProgress(wordId: wordId, direction: .recognize, status: .learnt))
        try database.upsertWordProgress(WordProgress(wordId: wordId, direction: .recall, status: .new))

        XCTAssertEqual(try database.fetchWordProgress().count, 2, "direction, not just wordId, is part of the primary key")
    }

    func testDeleteWordProgressForWordIdRemovesOnlyThatWordsRows() throws {
        let database = AppDatabase.makeInMemory()
        let targetWordId = UUID()
        let otherWordId = UUID()
        try database.replaceWordProgress([
            WordProgress(wordId: targetWordId, direction: .recognize, status: .new),
            WordProgress(wordId: targetWordId, direction: .recall, status: .new),
            WordProgress(wordId: otherWordId, direction: .recognize, status: .new),
        ])

        try database.deleteWordProgress(forWordId: targetWordId)

        XCTAssertEqual(try database.fetchWordProgress().map(\.wordId), [otherWordId])
    }

    func testDeletePendingReviewsForWordIdRemovesOnlyThatWordsQueuedReviews() throws {
        let database = AppDatabase.makeInMemory()
        let targetWordId = UUID()
        let otherWordId = UUID()

        func makeReview(wordId: UUID) -> PendingReview {
            let progress = WordProgress(wordId: wordId, direction: .recognize, status: .learning)
            let log = ReviewLogEntry(wordId: wordId, direction: .recognize, result: .know, phase: .active, statusBefore: .new, statusAfter: .learning)
            return PendingReview(outcome: ReviewScheduler.Outcome(progress: progress, log: log, activityDate: CalendarDay(date: Date())))
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
        let progress = WordProgress(wordId: word.id, direction: .recognize, status: .new)
        let collection = WordCollection(name: "n", targetLanguage: "es", nativeLanguage: "en")
        let activity = DailyActivity(activityDate: CalendarDay(date: Date()), reviewsCount: 1)
        try database.replaceWords([word])
        try database.replaceWordProgress([progress])
        try database.replaceCollections([collection])
        try database.replaceDailyActivity([activity])
        let outcome = ReviewScheduler.Outcome(
            progress: progress,
            log: ReviewLogEntry(wordId: word.id, direction: .recognize, result: .know, phase: .active, statusBefore: .new, statusAfter: .learning),
            activityDate: activity.activityDate
        )
        try database.enqueuePendingReview(PendingReview(outcome: outcome))

        try database.wipe()

        XCTAssertTrue(try database.fetchWords().isEmpty)
        XCTAssertTrue(try database.fetchWordProgress().isEmpty)
        XCTAssertTrue(try database.fetchCollections().isEmpty)
        XCTAssertTrue(try database.fetchDailyActivity().isEmpty)
        XCTAssertTrue(try database.fetchPendingReviews().isEmpty)
    }
}
