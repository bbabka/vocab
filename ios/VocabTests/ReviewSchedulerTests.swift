import XCTest
@testable import Vocab

final class ReviewSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func makeWord(
        status: WordStatus,
        knowCount: Int = 0,
        intervalStep: Int = 0,
        dueAt: Date? = nil,
        timesSeen: Int = 0
    ) -> Word {
        Word(
            collectionId: UUID(),
            term: "term",
            translation: "translation",
            status: status,
            importance: 2,
            knowCount: knowCount,
            intervalStep: intervalStep,
            dueAt: dueAt,
            timesSeen: timesSeen,
            createdAt: now.addingTimeInterval(-86400),
            updatedAt: now.addingTimeInterval(-86400)
        )
    }

    // MARK: - Canary: enum raw values must match the DB CHECK constraint

    func testWordStatusRawValuesMatchDatabaseCheckConstraint() {
        XCTAssertEqual(
            WordStatus.allCases.map(\.rawValue),
            ["new", "learning", "learnt", "retired"]
        )
    }

    func testPartOfSpeechRawValuesMatchDatabaseCheckConstraint() {
        XCTAssertEqual(
            PartOfSpeech.allCases.map(\.rawValue),
            ["noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "interjection", "other"]
        )
    }

    // MARK: - Phase 1: active deck (new/learning)

    func testNewWordKnowSwipeIncrementsKnowCountWithoutGraduating() {
        let word = makeWord(status: .new, knowCount: 0)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.word.knowCount, 1)
        XCTAssertEqual(outcome.word.status, .new)
        XCTAssertNil(outcome.word.dueAt)
    }

    func testLearningWordGraduatesOnReachingLearntThreshold() {
        let word = makeWord(status: .learning, knowCount: SchedulingConstants.learntThreshold - 1)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.word.knowCount, SchedulingConstants.learntThreshold)
        XCTAssertEqual(outcome.word.status, .learnt)
        XCTAssertEqual(outcome.word.intervalStep, 0)
        XCTAssertEqual(
            outcome.word.dueAt,
            calendar.date(byAdding: .day, value: SchedulingConstants.resurfaceLadderDays[0], to: now)
        )
    }

    func testLearningWordBelowThresholdStaysOnDeckAfterKnow() {
        let word = makeWord(status: .learning, knowCount: 0)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.word.knowCount, 1)
        XCTAssertEqual(outcome.word.status, .learning)
    }

    func testNewWordDontKnowResetsKnowCountAndPromotesToLearning() {
        let word = makeWord(status: .new, knowCount: 0)
        let outcome = ReviewScheduler.apply(.dontKnow, to: word, now: now)

        XCTAssertEqual(outcome.word.knowCount, 0)
        XCTAssertEqual(outcome.word.status, .learning)
    }

    func testLearningWordDontKnowResetsKnowCountAndStaysLearning() {
        let word = makeWord(status: .learning, knowCount: 2)
        let outcome = ReviewScheduler.apply(.dontKnow, to: word, now: now)

        XCTAssertEqual(outcome.word.knowCount, 0)
        XCTAssertEqual(outcome.word.status, .learning)
    }

    func testActiveDeckSkipChangesNoSchedulingFields() {
        let word = makeWord(status: .learning, knowCount: 1)
        let outcome = ReviewScheduler.apply(.skip, to: word, now: now)

        XCTAssertEqual(outcome.word.knowCount, 1)
        XCTAssertEqual(outcome.word.status, .learning)
    }

    // MARK: - Phase 2: resurface ladder (learnt)

    func testResurfaceKnowAdvancesLadderFromStep0To1() {
        let word = makeWord(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 0)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.word.intervalStep, 1)
        XCTAssertEqual(outcome.word.status, .learnt)
        XCTAssertEqual(
            outcome.word.dueAt,
            calendar.date(byAdding: .day, value: SchedulingConstants.resurfaceLadderDays[1], to: now)
        )
    }

    func testResurfaceKnowAdvancesLadderFromStep1To2() {
        let word = makeWord(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 1)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.word.intervalStep, 2)
        XCTAssertEqual(outcome.word.status, .learnt)
        XCTAssertEqual(
            outcome.word.dueAt,
            calendar.date(byAdding: .day, value: SchedulingConstants.resurfaceLadderDays[2], to: now)
        )
    }

    func testResurfaceKnowPastLadderEndRetiresWord() {
        let word = makeWord(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 2)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.word.intervalStep, 3)
        XCTAssertEqual(outcome.word.status, .retired)
    }

    func testResurfaceDontKnowFullyDemotesWordToActiveDeck() {
        let word = makeWord(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 2, dueAt: now)
        let outcome = ReviewScheduler.apply(.dontKnow, to: word, now: now)

        XCTAssertEqual(outcome.word.status, .learning)
        XCTAssertEqual(outcome.word.knowCount, 0)
        XCTAssertEqual(outcome.word.intervalStep, 0)
        XCTAssertNil(outcome.word.dueAt)
    }

    func testResurfaceSkipChangesNoSchedulingFields() {
        let dueAt = now
        let word = makeWord(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 1, dueAt: dueAt)
        let outcome = ReviewScheduler.apply(.skip, to: word, now: now)

        XCTAssertEqual(outcome.word.intervalStep, 1)
        XCTAssertEqual(outcome.word.status, .learnt)
        XCTAssertEqual(outcome.word.dueAt, dueAt)
    }

    // MARK: - Every swipe, both phases

    func testEverySwipeIncrementsTimesSeenBumpsUpdatedAtAndLogsCorrectly() {
        let word = makeWord(status: .new, timesSeen: 4)
        let outcome = ReviewScheduler.apply(.dontKnow, to: word, now: now)

        XCTAssertEqual(outcome.word.timesSeen, 5)
        XCTAssertEqual(outcome.word.updatedAt, now)
        XCTAssertEqual(outcome.log.wordId, word.id)
        XCTAssertEqual(outcome.log.result, .dontKnow)
        XCTAssertEqual(outcome.log.phase, .active)
        XCTAssertEqual(outcome.log.statusBefore, .new)
        XCTAssertEqual(outcome.log.statusAfter, .learning)
        XCTAssertEqual(outcome.log.reviewedAt, now)
    }

    func testResurfaceLogRecordsResurfacePhase() {
        let word = makeWord(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 0)
        let outcome = ReviewScheduler.apply(.know, to: word, now: now)

        XCTAssertEqual(outcome.log.phase, .resurface)
        XCTAssertEqual(outcome.log.statusBefore, .learnt)
        XCTAssertEqual(outcome.log.statusAfter, .learnt)
        XCTAssertEqual(outcome.activityDate, CalendarDay(date: now, calendar: calendar))
    }
}
