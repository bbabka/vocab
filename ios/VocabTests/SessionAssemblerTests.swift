import XCTest
@testable import Vocab

final class SessionAssemblerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let collectionId = UUID()

    private func makeWord(
        status: WordStatus,
        importance: Int = 2,
        knowCount: Int = 0,
        dueAt: Date? = nil,
        createdAt: Date
    ) -> Word {
        Word(
            collectionId: collectionId,
            term: UUID().uuidString,
            translation: "t",
            status: status,
            importance: importance,
            knowCount: knowCount,
            dueAt: dueAt,
            createdAt: createdAt
        )
    }

    func testDueResurfaceWordsOrderedByDueAtAscending() {
        let later = makeWord(status: .learnt, dueAt: now.addingTimeInterval(-100), createdAt: now)
        let sooner = makeWord(status: .learnt, dueAt: now.addingTimeInterval(-1000), createdAt: now)

        let batch = ReviewScheduler.assembleBatch(from: [later, sooner], batchSize: 10, now: now)

        XCTAssertEqual(batch.map(\.id), [sooner.id, later.id])
    }

    func testNotYetDueResurfaceWordsAreExcluded() {
        let notDue = makeWord(status: .learnt, dueAt: now.addingTimeInterval(1000), createdAt: now)

        let batch = ReviewScheduler.assembleBatch(from: [notDue], batchSize: 10, now: now)

        XCTAssertTrue(batch.isEmpty)
    }

    func testActiveDeckOrderedByImportanceDescThenKnowCountAscThenCreatedAtAsc() {
        let lowImportance = makeWord(status: .new, importance: 1, createdAt: now)
        let highImportanceOlder = makeWord(status: .new, importance: 3, createdAt: now.addingTimeInterval(-100))
        let highImportanceNewerLowKnowCount = makeWord(
            status: .learning, importance: 3, knowCount: 0, createdAt: now.addingTimeInterval(-10)
        )
        let highImportanceHighKnowCount = makeWord(
            status: .learning, importance: 3, knowCount: 2, createdAt: now.addingTimeInterval(-200)
        )

        let batch = ReviewScheduler.assembleBatch(
            from: [lowImportance, highImportanceOlder, highImportanceNewerLowKnowCount, highImportanceHighKnowCount],
            batchSize: 10,
            now: now
        )

        XCTAssertEqual(
            batch.map(\.id),
            [highImportanceOlder.id, highImportanceNewerLowKnowCount.id, highImportanceHighKnowCount.id, lowImportance.id]
        )
    }

    func testResurfaceCappedAtRoughlyOneThirdOfBatchBackfilledFromActiveDeck() {
        let dueResurface = (0..<6).map { offset in
            makeWord(status: .learnt, dueAt: now.addingTimeInterval(-Double(offset) - 1), createdAt: now)
        }
        let activeDeck = (0..<6).map { offset in
            makeWord(status: .new, createdAt: now.addingTimeInterval(-Double(offset)))
        }

        let batch = ReviewScheduler.assembleBatch(from: dueResurface + activeDeck, batchSize: 9, now: now)

        XCTAssertEqual(batch.count, 9)
        let resurfaceInBatch = batch.filter { $0.status == .learnt }
        XCTAssertEqual(resurfaceInBatch.count, 3, "resurface share should cap at floor(9 * 1/3) = 3")
        XCTAssertEqual(batch.count - resurfaceInBatch.count, 6, "remainder should backfill from the active deck")
    }

    func testBatchCappedAtBatchSizeEvenWithMoreWordsAvailable() {
        let activeDeck = (0..<50).map { offset in
            makeWord(status: .new, createdAt: now.addingTimeInterval(-Double(offset)))
        }

        let batch = ReviewScheduler.assembleBatch(from: activeDeck, batchSize: 20, now: now)

        XCTAssertEqual(batch.count, 20)
    }

    func testEmptyPoolProducesEmptyBatchAndIsFullyRetired() {
        let batch = ReviewScheduler.assembleBatch(from: [], batchSize: 10, now: now)
        XCTAssertTrue(batch.isEmpty)
        XCTAssertTrue(ReviewScheduler.isFullyRetired([], now: now))
    }

    func testIsFullyRetiredFiresWheneverNothingIsDueAndActiveDeckIsEmpty() {
        // Per the brief: "If nothing is due and the deck is empty, the
        // collection is fully retired — show a 'nothing to review' state."
        // This fires for a genuinely all-retired pool...
        let retired = makeWord(status: .retired, createdAt: now)
        XCTAssertTrue(ReviewScheduler.assembleBatch(from: [retired], batchSize: 10, now: now).isEmpty)
        XCTAssertTrue(ReviewScheduler.isFullyRetired([retired], now: now))

        // ...and equally for a learnt word that's just not due yet, since
        // the brief's condition is "nothing due + deck empty," not "every
        // word has reached terminal retired status."
        let notDueYet = makeWord(status: .learnt, dueAt: now.addingTimeInterval(1000), createdAt: now)
        XCTAssertTrue(ReviewScheduler.assembleBatch(from: [notDueYet], batchSize: 10, now: now).isEmpty)
        XCTAssertTrue(ReviewScheduler.isFullyRetired([notDueYet], now: now))
    }

    func testOverdueBacklogBeyondCapDrainsFIFOAcrossSessions() {
        // Simulates the brief's accepted v1 backlog behavior: more due
        // resurface words than the ~1/3 cap, so only the oldest-due subset
        // is admitted this session; the rest remain due for next time.
        let overdue = (0..<10).map { offset in
            makeWord(status: .learnt, dueAt: now.addingTimeInterval(-Double(1000 - offset)), createdAt: now)
        }

        let firstSessionBatch = ReviewScheduler.assembleBatch(from: overdue, batchSize: 9, now: now)
        let resurfaceCap = 3
        XCTAssertEqual(firstSessionBatch.count, resurfaceCap)
        XCTAssertEqual(
            Set(firstSessionBatch.map(\.id)),
            Set(overdue.prefix(resurfaceCap).map(\.id)),
            "oldest-due words should be admitted first"
        )
    }
}
