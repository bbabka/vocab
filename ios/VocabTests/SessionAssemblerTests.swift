import XCTest
@testable import Vocab

final class SessionAssemblerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let collectionId = UUID()

    /// Builds a (word, progress) pair sharing an id — `assembleBatch` reads
    /// `importance`/`createdAt` off `Word` and `status`/`knowCount`/`dueAt`
    /// off `WordProgress`, joined by `wordId`.
    private func makeCard(
        status: WordStatus,
        importance: Int = 2,
        knowCount: Int = 0,
        dueAt: Date? = nil,
        createdAt: Date
    ) -> (word: Word, progress: WordProgress) {
        let word = Word(collectionId: collectionId, term: UUID().uuidString, translation: "t", importance: importance, createdAt: createdAt)
        let progress = WordProgress(wordId: word.id, direction: .recognize, status: status, knowCount: knowCount, dueAt: dueAt)
        return (word, progress)
    }

    private func assembleBatch(_ cards: [(word: Word, progress: WordProgress)], batchSize: Int) -> [PracticeCard] {
        ReviewScheduler.assembleBatch(from: cards.map(\.word), progress: cards.map(\.progress), direction: .recognize, batchSize: batchSize, now: now)
    }

    private func isFullyRetired(_ cards: [(word: Word, progress: WordProgress)]) -> Bool {
        ReviewScheduler.isFullyRetired(cards.map(\.progress), words: cards.map(\.word), direction: .recognize, now: now)
    }

    func testDueResurfaceWordsOrderedByDueAtAscending() {
        let later = makeCard(status: .learnt, dueAt: now.addingTimeInterval(-100), createdAt: now)
        let sooner = makeCard(status: .learnt, dueAt: now.addingTimeInterval(-1000), createdAt: now)

        let batch = assembleBatch([later, sooner], batchSize: 10)

        XCTAssertEqual(batch.map(\.id), [sooner.word.id, later.word.id])
    }

    func testNotYetDueResurfaceWordsAreExcluded() {
        let notDue = makeCard(status: .learnt, dueAt: now.addingTimeInterval(1000), createdAt: now)

        let batch = assembleBatch([notDue], batchSize: 10)

        XCTAssertTrue(batch.isEmpty)
    }

    func testActiveDeckOrderedByImportanceDescThenKnowCountAscThenCreatedAtAsc() {
        let lowImportance = makeCard(status: .new, importance: 1, createdAt: now)
        let highImportanceOlder = makeCard(status: .new, importance: 3, createdAt: now.addingTimeInterval(-100))
        let highImportanceNewerLowKnowCount = makeCard(
            status: .learning, importance: 3, knowCount: 0, createdAt: now.addingTimeInterval(-10)
        )
        let highImportanceHighKnowCount = makeCard(
            status: .learning, importance: 3, knowCount: 2, createdAt: now.addingTimeInterval(-200)
        )

        let batch = assembleBatch(
            [lowImportance, highImportanceOlder, highImportanceNewerLowKnowCount, highImportanceHighKnowCount],
            batchSize: 10
        )

        XCTAssertEqual(
            batch.map(\.id),
            [highImportanceOlder.word.id, highImportanceNewerLowKnowCount.word.id, highImportanceHighKnowCount.word.id, lowImportance.word.id]
        )
    }

    func testResurfaceCappedAtRoughlyOneThirdOfBatchBackfilledFromActiveDeck() {
        let dueResurface = (0..<6).map { offset in
            makeCard(status: .learnt, dueAt: now.addingTimeInterval(-Double(offset) - 1), createdAt: now)
        }
        let activeDeck = (0..<6).map { offset in
            makeCard(status: .new, createdAt: now.addingTimeInterval(-Double(offset)))
        }

        let batch = assembleBatch(dueResurface + activeDeck, batchSize: 9)

        XCTAssertEqual(batch.count, 9)
        let resurfaceInBatch = batch.filter { $0.progress.status == .learnt }
        XCTAssertEqual(resurfaceInBatch.count, 3, "resurface share should cap at floor(9 * 1/3) = 3")
        XCTAssertEqual(batch.count - resurfaceInBatch.count, 6, "remainder should backfill from the active deck")
    }

    func testBatchCappedAtBatchSizeEvenWithMoreWordsAvailable() {
        let activeDeck = (0..<50).map { offset in
            makeCard(status: .new, createdAt: now.addingTimeInterval(-Double(offset)))
        }

        let batch = assembleBatch(activeDeck, batchSize: 20)

        XCTAssertEqual(batch.count, 20)
    }

    func testEmptyPoolProducesEmptyBatchAndIsFullyRetired() {
        let batch = assembleBatch([], batchSize: 10)
        XCTAssertTrue(batch.isEmpty)
        XCTAssertTrue(isFullyRetired([]))
    }

    func testIsFullyRetiredFiresWheneverNothingIsDueAndActiveDeckIsEmpty() {
        // Per the brief: "If nothing is due and the deck is empty, the
        // collection is fully retired — show a 'nothing to review' state."
        // This fires for a genuinely all-retired pool...
        let retired = makeCard(status: .retired, createdAt: now)
        XCTAssertTrue(assembleBatch([retired], batchSize: 10).isEmpty)
        XCTAssertTrue(isFullyRetired([retired]))

        // ...and equally for a learnt word that's just not due yet, since
        // the brief's condition is "nothing due + deck empty," not "every
        // word has reached terminal retired status."
        let notDueYet = makeCard(status: .learnt, dueAt: now.addingTimeInterval(1000), createdAt: now)
        XCTAssertTrue(assembleBatch([notDueYet], batchSize: 10).isEmpty)
        XCTAssertTrue(isFullyRetired([notDueYet]))
    }

    func testOverdueBacklogBeyondCapDrainsFIFOAcrossSessions() {
        // Simulates the brief's accepted v1 backlog behavior: more due
        // resurface words than the ~1/3 cap, so only the oldest-due subset
        // is admitted this session; the rest remain due for next time.
        let overdue = (0..<10).map { offset in
            makeCard(status: .learnt, dueAt: now.addingTimeInterval(-Double(1000 - offset)), createdAt: now)
        }

        let firstSessionBatch = assembleBatch(overdue, batchSize: 9)
        let resurfaceCap = 3
        XCTAssertEqual(firstSessionBatch.count, resurfaceCap)
        XCTAssertEqual(
            Set(firstSessionBatch.map(\.id)),
            Set(overdue.prefix(resurfaceCap).map(\.word.id)),
            "oldest-due words should be admitted first"
        )
    }
}
