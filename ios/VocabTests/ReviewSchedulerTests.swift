import XCTest
@testable import Vocab

final class ReviewSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func makeProgress(
        wordId: UUID = UUID(),
        direction: PracticeDirection = .recognize,
        status: WordStatus,
        knowCount: Int = 0,
        intervalStep: Int = 0,
        dueAt: Date? = nil,
        timesSeen: Int = 0
    ) -> WordProgress {
        WordProgress(
            wordId: wordId,
            direction: direction,
            status: status,
            knowCount: knowCount,
            intervalStep: intervalStep,
            dueAt: dueAt,
            timesSeen: timesSeen,
            updatedAt: now.addingTimeInterval(-86400)
        )
    }

    // MARK: - Canary: enum raw values must match the DB CHECK constraints

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

    func testPracticeDirectionRawValuesMatchDatabaseCheckConstraint() {
        XCTAssertEqual(PracticeDirection.allCases.map(\.rawValue), ["recognize", "recall"])
    }

    // MARK: - Phase 1: active deck (new/learning)

    func testNewWordKnowSwipeIncrementsKnowCountWithoutGraduating() {
        let progress = makeProgress(status: .new, knowCount: 0)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.knowCount, 1)
        XCTAssertEqual(outcome.progress.status, .new)
        XCTAssertNil(outcome.progress.dueAt)
    }

    func testLearningWordGraduatesOnReachingLearntThreshold() {
        let progress = makeProgress(status: .learning, knowCount: SchedulingConstants.learntThreshold - 1)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.knowCount, SchedulingConstants.learntThreshold)
        XCTAssertEqual(outcome.progress.status, .learnt)
        XCTAssertEqual(outcome.progress.intervalStep, 0)
        XCTAssertEqual(
            outcome.progress.dueAt,
            calendar.date(byAdding: .day, value: SchedulingConstants.resurfaceLadderDays[0], to: now)
        )
    }

    func testLearningWordBelowThresholdStaysOnDeckAfterKnow() {
        let progress = makeProgress(status: .learning, knowCount: 0)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.knowCount, 1)
        XCTAssertEqual(outcome.progress.status, .learning)
    }

    func testNewWordDontKnowResetsKnowCountAndPromotesToLearning() {
        let progress = makeProgress(status: .new, knowCount: 0)
        let outcome = ReviewScheduler.apply(.dontKnow, to: progress, now: now)

        XCTAssertEqual(outcome.progress.knowCount, 0)
        XCTAssertEqual(outcome.progress.status, .learning)
    }

    func testLearningWordDontKnowResetsKnowCountAndStaysLearning() {
        let progress = makeProgress(status: .learning, knowCount: 2)
        let outcome = ReviewScheduler.apply(.dontKnow, to: progress, now: now)

        XCTAssertEqual(outcome.progress.knowCount, 0)
        XCTAssertEqual(outcome.progress.status, .learning)
    }

    func testActiveDeckSkipChangesNoSchedulingFields() {
        let progress = makeProgress(status: .learning, knowCount: 1)
        let outcome = ReviewScheduler.apply(.skip, to: progress, now: now)

        XCTAssertEqual(outcome.progress.knowCount, 1)
        XCTAssertEqual(outcome.progress.status, .learning)
    }

    // MARK: - Phase 2: resurface ladder (learnt)

    func testResurfaceKnowAdvancesLadderFromStep0To1() {
        let progress = makeProgress(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 0)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.intervalStep, 1)
        XCTAssertEqual(outcome.progress.status, .learnt)
        XCTAssertEqual(
            outcome.progress.dueAt,
            calendar.date(byAdding: .day, value: SchedulingConstants.resurfaceLadderDays[1], to: now)
        )
    }

    func testResurfaceKnowAdvancesLadderFromStep1To2() {
        let progress = makeProgress(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 1)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.intervalStep, 2)
        XCTAssertEqual(outcome.progress.status, .learnt)
        XCTAssertEqual(
            outcome.progress.dueAt,
            calendar.date(byAdding: .day, value: SchedulingConstants.resurfaceLadderDays[2], to: now)
        )
    }

    func testResurfaceKnowPastLadderEndRetiresWord() {
        let progress = makeProgress(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 2)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.intervalStep, 3)
        XCTAssertEqual(outcome.progress.status, .retired)
    }

    func testResurfaceDontKnowFullyDemotesWordToActiveDeck() {
        let progress = makeProgress(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 2, dueAt: now)
        let outcome = ReviewScheduler.apply(.dontKnow, to: progress, now: now)

        XCTAssertEqual(outcome.progress.status, .learning)
        XCTAssertEqual(outcome.progress.knowCount, 0)
        XCTAssertEqual(outcome.progress.intervalStep, 0)
        XCTAssertNil(outcome.progress.dueAt)
    }

    func testResurfaceSkipChangesNoSchedulingFields() {
        let dueAt = now
        let progress = makeProgress(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 1, dueAt: dueAt)
        let outcome = ReviewScheduler.apply(.skip, to: progress, now: now)

        XCTAssertEqual(outcome.progress.intervalStep, 1)
        XCTAssertEqual(outcome.progress.status, .learnt)
        XCTAssertEqual(outcome.progress.dueAt, dueAt)
    }

    // MARK: - Every swipe, both phases

    func testEverySwipeIncrementsTimesSeenBumpsUpdatedAtAndLogsCorrectly() {
        let progress = makeProgress(status: .new, timesSeen: 4)
        let outcome = ReviewScheduler.apply(.dontKnow, to: progress, now: now)

        XCTAssertEqual(outcome.progress.timesSeen, 5)
        XCTAssertEqual(outcome.progress.updatedAt, now)
        XCTAssertEqual(outcome.log.wordId, progress.wordId)
        XCTAssertEqual(outcome.log.direction, .recognize)
        XCTAssertEqual(outcome.log.result, .dontKnow)
        XCTAssertEqual(outcome.log.phase, .active)
        XCTAssertEqual(outcome.log.statusBefore, .new)
        XCTAssertEqual(outcome.log.statusAfter, .learning)
        XCTAssertEqual(outcome.log.reviewedAt, now)
    }

    func testResurfaceLogRecordsResurfacePhase() {
        let progress = makeProgress(status: .learnt, knowCount: SchedulingConstants.learntThreshold, intervalStep: 0)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.log.phase, .resurface)
        XCTAssertEqual(outcome.log.statusBefore, .learnt)
        XCTAssertEqual(outcome.log.statusAfter, .learnt)
        XCTAssertEqual(outcome.activityDate, CalendarDay(date: now, calendar: calendar))
    }

    func testApplyPreservesTheDirectionItWasGivenInTheLog() {
        let progress = makeProgress(direction: .recall, status: .new)
        let outcome = ReviewScheduler.apply(.know, to: progress, now: now)

        XCTAssertEqual(outcome.progress.direction, .recall)
        XCTAssertEqual(outcome.log.direction, .recall)
    }

    // MARK: - assembleBatch: direction filtering and recall eligibility

    private func makeWord(meanings: [WordMeaning] = [WordMeaning(translation: "t")], createdAt: Date = Date(), importance: Int = 2) -> Word {
        Word(collectionId: UUID(), term: "term", meanings: meanings, importance: importance, createdAt: createdAt)
    }

    func testAssembleBatchOnlyReturnsProgressForTheRequestedDirection() {
        let word = makeWord()
        let recognizeProgress = makeProgress(wordId: word.id, direction: .recognize, status: .new)
        let recallProgress = makeProgress(wordId: word.id, direction: .recall, status: .new)

        let recognizeBatch = ReviewScheduler.assembleBatch(from: [word], progress: [recognizeProgress, recallProgress], direction: .recognize, batchSize: 10, now: now)
        let recallBatch = ReviewScheduler.assembleBatch(from: [word], progress: [recognizeProgress, recallProgress], direction: .recall, batchSize: 10, now: now)

        XCTAssertEqual(recognizeBatch.map(\.progress.direction), [.recognize])
        XCTAssertEqual(recallBatch.map(\.progress.direction), [.recall])
    }

    func testAssembleBatchExcludesRecallCardsForWordsWithNoMeanings() {
        let word = makeWord(meanings: [])
        let recallProgress = makeProgress(wordId: word.id, direction: .recall, status: .new)

        let recallBatch = ReviewScheduler.assembleBatch(from: [word], progress: [recallProgress], direction: .recall, batchSize: 10, now: now)

        XCTAssertTrue(recallBatch.isEmpty, "an empty meanings list would render a blank recall prompt")
    }

    func testAssembleBatchIncludesRecognizeCardsForWordsWithNoMeaningsUnlikeRecall() {
        let word = makeWord(meanings: [])
        let recognizeProgress = makeProgress(wordId: word.id, direction: .recognize, status: .new)

        let recognizeBatch = ReviewScheduler.assembleBatch(from: [word], progress: [recognizeProgress], direction: .recognize, batchSize: 10, now: now)

        XCTAssertEqual(recognizeBatch.map(\.word.id), [word.id], "recognize's prompt is the term, which always exists")
    }

    func testIsFullyRetiredOnlyConsidersTheRequestedDirection() {
        let word = makeWord()
        let recognizeDone = makeProgress(wordId: word.id, direction: .recognize, status: .retired)
        let recallActive = makeProgress(wordId: word.id, direction: .recall, status: .new)

        XCTAssertTrue(ReviewScheduler.isFullyRetired([recognizeDone, recallActive], direction: .recognize, now: now))
        XCTAssertFalse(ReviewScheduler.isFullyRetired([recognizeDone, recallActive], direction: .recall, now: now))
    }
}
