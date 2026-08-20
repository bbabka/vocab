import XCTest
@testable import Vocab

@MainActor
final class WordStoreTests: XCTestCase {
    private let collectionId = UUID()

    private func makeWord(collectionId: UUID? = nil, meanings: [WordMeaning] = [WordMeaning(translation: "translation")]) -> Word {
        Word(collectionId: collectionId ?? self.collectionId, term: "term", meanings: meanings)
    }

    private func makeProgress(for word: Word, direction: PracticeDirection = .recognize, status: WordStatus = .new, knowCount: Int = 0) -> WordProgress {
        WordProgress(wordId: word.id, direction: direction, status: status, knowCount: knowCount)
    }

    private func makeStore(words: [Word] = MockData.words, wordProgress: [WordProgress] = MockData.wordProgress) -> WordStore {
        WordStore(words: words, wordProgress: wordProgress, database: .makeInMemory())
    }

    func testDefaultInitSeedsFromMockData() {
        let store = makeStore()
        XCTAssertEqual(store.words.map(\.id), MockData.words.map(\.id))
        XCTAssertEqual(store.wordProgress.count, MockData.wordProgress.count)
    }

    func testWordsInFiltersByCollection() {
        let inCollection = makeWord()
        let other = makeWord(collectionId: UUID())
        let store = makeStore(words: [inCollection, other], wordProgress: [])

        XCTAssertEqual(store.words(in: collectionId).map(\.id), [inCollection.id])
    }

    // MARK: - assembleBatch/isFullyRetired collection and direction filtering

    func testAssembleBatchWithNilCollectionIdsPullsFromEveryCollection() {
        let inCollection = makeWord()
        let other = makeWord(collectionId: UUID())
        let progress = [makeProgress(for: inCollection), makeProgress(for: other)]
        let store = makeStore(words: [inCollection, other], wordProgress: progress)

        let batch = store.assembleBatch(collectionIds: nil, direction: .recognize, batchSize: 10)

        XCTAssertEqual(Set(batch.map(\.id)), [inCollection.id, other.id])
    }

    func testAssembleBatchWithEmptyCollectionIdsPullsFromEveryCollection() {
        let inCollection = makeWord()
        let other = makeWord(collectionId: UUID())
        let progress = [makeProgress(for: inCollection), makeProgress(for: other)]
        let store = makeStore(words: [inCollection, other], wordProgress: progress)

        let batch = store.assembleBatch(collectionIds: [], direction: .recognize, batchSize: 10)

        XCTAssertEqual(Set(batch.map(\.id)), [inCollection.id, other.id])
    }

    func testAssembleBatchWithMultipleCollectionIdsUnionsTheirWords() {
        let otherCollectionId = UUID()
        let inFirstCollection = makeWord()
        let inSecondCollection = makeWord(collectionId: otherCollectionId)
        let inThirdCollection = makeWord(collectionId: UUID())
        let progress = [inFirstCollection, inSecondCollection, inThirdCollection].map { makeProgress(for: $0) }
        let store = makeStore(words: [inFirstCollection, inSecondCollection, inThirdCollection], wordProgress: progress)

        let batch = store.assembleBatch(collectionIds: [collectionId, otherCollectionId], direction: .recognize, batchSize: 10)

        XCTAssertEqual(Set(batch.map(\.id)), [inFirstCollection.id, inSecondCollection.id])
    }

    func testAssembleBatchOnlyReturnsTheRequestedDirection() {
        let word = makeWord()
        let progress = [makeProgress(for: word, direction: .recognize), makeProgress(for: word, direction: .recall)]
        let store = makeStore(words: [word], wordProgress: progress)

        let recallBatch = store.assembleBatch(collectionIds: [collectionId], direction: .recall, batchSize: 10)

        XCTAssertEqual(recallBatch.map(\.progress.direction), [.recall])
    }

    func testIsFullyRetiredOnlyConsidersSelectedCollections() {
        let retiredElsewhere = makeWord()
        let dueInOtherCollection = makeWord(collectionId: UUID())
        let progress = [
            makeProgress(for: retiredElsewhere, status: .retired),
            makeProgress(for: dueInOtherCollection, status: .new),
        ]
        let store = makeStore(words: [retiredElsewhere, dueInOtherCollection], wordProgress: progress)

        XCTAssertTrue(store.isFullyRetired(collectionIds: [collectionId], direction: .recognize))
        XCTAssertFalse(store.isFullyRetired(collectionIds: [collectionId, dueInOtherCollection.collectionId], direction: .recognize))
    }

    // MARK: - add/delete

    func testAddAppendsWordAndItsOptimisticRecognizeProgressRow() {
        let store = makeStore(words: [], wordProgress: [])
        let word = makeWord()

        store.add(word)

        XCTAssertEqual(store.words, [word])
        XCTAssertEqual(store.wordProgress.map(\.wordId), [word.id])
        XCTAssertEqual(store.wordProgress.first?.direction, .recognize)
        XCTAssertEqual(store.wordProgress.first?.status, .new)
    }

    func testDeleteRemovesOnlyTheMatchingWordAndItsProgressRows() {
        let target = makeWord()
        let other = makeWord()
        let progress = [
            makeProgress(for: target, direction: .recognize),
            makeProgress(for: target, direction: .recall),
            makeProgress(for: other, direction: .recognize),
        ]
        let store = makeStore(words: [target, other], wordProgress: progress)

        store.delete(target.id)

        XCTAssertEqual(store.words.map(\.id), [other.id])
        XCTAssertEqual(store.wordProgress.map(\.wordId), [other.id])
    }

    // MARK: - applySwipe

    func testApplySwipeUpdatesTheStoredProgressOptimistically() {
        let word = makeWord()
        let store = makeStore(words: [word], wordProgress: [makeProgress(for: word, knowCount: 0)])

        let outcome = store.applySwipe(.know, to: word.id, direction: .recognize, now: Date())

        XCTAssertNotNil(outcome)
        XCTAssertEqual(store.recognizeProgress(for: word.id)?.knowCount, 1)
    }

    func testApplySwipeOnUnknownWordIdIsANoOp() {
        let store = makeStore(words: [], wordProgress: [])
        let outcome = store.applySwipe(.know, to: UUID(), direction: .recognize, now: Date())
        XCTAssertNil(outcome)
    }

    func testApplySwipeOnlyTouchesTheGivenDirectionsProgress() {
        let word = makeWord()
        let progress = [
            makeProgress(for: word, direction: .recognize, knowCount: 0),
            makeProgress(for: word, direction: .recall, knowCount: 0),
        ]
        let store = makeStore(words: [word], wordProgress: progress)

        store.applySwipe(.know, to: word.id, direction: .recall, now: Date())

        XCTAssertEqual(store.recognizeProgress(for: word.id)?.knowCount, 0, "a recall swipe must not touch recognize's progress")
        XCTAssertEqual(store.wordProgress.first { $0.direction == .recall }?.knowCount, 1)
    }

    // MARK: - setStatus (manual override, always targets recognize)

    func testSetStatusToLearntResetsSchedulingFieldsToSensibleDefaults() {
        let word = makeWord()
        let store = makeStore(words: [word], wordProgress: [makeProgress(for: word, status: .new, knowCount: 2)])

        store.setStatus(.learnt, for: word.id, now: Date(timeIntervalSince1970: 1_700_000_000))

        let updated = store.recognizeProgress(for: word.id)!
        XCTAssertEqual(updated.status, .learnt)
        XCTAssertEqual(updated.intervalStep, 0)
        XCTAssertNotNil(updated.dueAt)
    }

    func testSetStatusToLearningResetsBackToDeckDefaults() {
        let word = makeWord()
        let store = makeStore(words: [word], wordProgress: [makeProgress(for: word, status: .learnt, knowCount: 3)])

        store.setStatus(.learning, for: word.id)

        let updated = store.recognizeProgress(for: word.id)!
        XCTAssertEqual(updated.status, .learning)
        XCTAssertEqual(updated.knowCount, 0)
        XCTAssertNil(updated.dueAt)
    }

    // MARK: - Outbox: applySwipe enqueues a durable pending_reviews row

    func testApplySwipeEnqueuesAPendingReviewSurvivingRestart() {
        let database = AppDatabase.makeInMemory()
        let word = makeWord()
        let store = WordStore(words: [word], wordProgress: [makeProgress(for: word)], database: database, reviewSyncing: NeverSucceedingReviewSyncing())

        let outcome = store.applySwipe(.know, to: word.id, direction: .recognize, now: Date(timeIntervalSince1970: 1_700_000_000))

        let pending = try! database.fetchPendingReviews()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, outcome?.log.id)
        XCTAssertEqual(pending.first?.wordId, word.id)
        XCTAssertEqual(pending.first?.direction, .recognize)
        XCTAssertEqual(pending.first?.knowCountAfter, 1)
    }

    // MARK: - loadFromRemote reconciliation (words)

    func testReconcileKeepsLocalWordWhenAPendingReviewExistsForIt() {
        var local = makeWord()
        local.term = "local edit"
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.term = "stale server copy" // predates the queued swipe
        remote.updatedAt = Date(timeIntervalSince1970: 2_000) // even "newer" by clock

        let reconciled = WordStore.reconcile(remote: [remote], local: [local], pendingWordIds: [local.id])

        XCTAssertEqual(reconciled.first?.term, "local edit", "a pending outbox entry means local is ahead regardless of updatedAt")
    }

    func testReconcilePrefersNewerRemoteWhenNoPendingReviewExists() {
        var local = makeWord()
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.term = "updated elsewhere"
        remote.updatedAt = Date(timeIntervalSince1970: 2_000)

        let reconciled = WordStore.reconcile(remote: [remote], local: [local], pendingWordIds: [])

        XCTAssertEqual(reconciled.first?.term, "updated elsewhere")
    }

    func testReconcileKeepsNewerLocalWhenNoPendingReviewExists() {
        var local = makeWord()
        local.term = "local edit"
        local.updatedAt = Date(timeIntervalSince1970: 2_000)
        var remote = local
        remote.term = "stale remote"
        remote.updatedAt = Date(timeIntervalSince1970: 1_000)

        let reconciled = WordStore.reconcile(remote: [remote], local: [local], pendingWordIds: [])

        XCTAssertEqual(reconciled.first?.term, "local edit")
    }

    // MARK: - loadFromRemote reconciliation (word_progress)

    func testReconcileProgressKeepsLocalWhenAPendingReviewExistsForItsKey() {
        let word = makeWord()
        var local = makeProgress(for: word, knowCount: 2)
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.knowCount = 0 // stale server copy, predates the queued swipe
        remote.updatedAt = Date(timeIntervalSince1970: 2_000) // even "newer" by clock

        let reconciled = WordStore.reconcileProgress(remote: [remote], local: [local], pendingKeys: [local.key])

        XCTAssertEqual(reconciled.first?.knowCount, 2)
    }

    func testReconcileProgressPrefersNewerRemoteWhenNoPendingReviewExists() {
        let word = makeWord()
        var local = makeProgress(for: word, knowCount: 1)
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.knowCount = 2
        remote.updatedAt = Date(timeIntervalSince1970: 2_000)

        let reconciled = WordStore.reconcileProgress(remote: [remote], local: [local], pendingKeys: [])

        XCTAssertEqual(reconciled.first?.knowCount, 2)
    }

    // MARK: - applyRealtimeChange (single-row upsert/delete) — words

    func testRealtimeUpsertSkipsWhenAPendingReviewExistsForThatWord() {
        let word = makeWord()

        let result = WordStore.applyingRealtimeUpsert(word, into: [word], pendingWordIds: [word.id])

        XCTAssertNil(result, "local outbox state is ahead; the incoming row must not overwrite it")
    }

    func testRealtimeUpsertSkipsAStaleOutOfOrderRow() {
        var local = makeWord()
        local.updatedAt = Date(timeIntervalSince1970: 2_000)
        var staleRemote = local
        staleRemote.term = "older write"
        staleRemote.updatedAt = Date(timeIntervalSince1970: 1_000)

        let result = WordStore.applyingRealtimeUpsert(staleRemote, into: [local], pendingWordIds: [])

        XCTAssertNil(result)
    }

    func testRealtimeUpsertAppliesANewerRow() {
        var local = makeWord()
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.term = "updated elsewhere"
        remote.updatedAt = Date(timeIntervalSince1970: 2_000)

        let result = WordStore.applyingRealtimeUpsert(remote, into: [local], pendingWordIds: [])

        XCTAssertEqual(result?.first?.term, "updated elsewhere")
    }

    func testRealtimeUpsertAppendsAWordNotYetKnownLocally() {
        let remote = makeWord()

        let result = WordStore.applyingRealtimeUpsert(remote, into: [], pendingWordIds: [])

        XCTAssertEqual(result, [remote])
    }

    func testRealtimeDeleteRemovesOnlyTheMatchingWord() {
        let target = makeWord()
        let other = makeWord()

        let result = WordStore.applyingRealtimeDelete(target.id, from: [target, other])

        XCTAssertEqual(result, [other])
    }

    // MARK: - applyRealtimeProgressChange (single-row upsert/delete) — word_progress

    func testRealtimeProgressUpsertSkipsWhenAPendingReviewExistsForThatKey() {
        let word = makeWord()
        let progress = makeProgress(for: word)

        let result = WordStore.applyingRealtimeProgressUpsert(progress, into: [progress], pendingKeys: [progress.key])

        XCTAssertNil(result)
    }

    func testRealtimeProgressUpsertAppliesANewerRow() {
        let word = makeWord()
        var local = makeProgress(for: word, knowCount: 1)
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.knowCount = 2
        remote.updatedAt = Date(timeIntervalSince1970: 2_000)

        let result = WordStore.applyingRealtimeProgressUpsert(remote, into: [local], pendingKeys: [])

        XCTAssertEqual(result?.first?.knowCount, 2)
    }

    func testRealtimeProgressDeleteRemovesOnlyTheMatchingKey() {
        let word = makeWord()
        let recognize = makeProgress(for: word, direction: .recognize)
        let recall = makeProgress(for: word, direction: .recall)

        let result = WordStore.applyingRealtimeProgressDelete(recognize.key, from: [recognize, recall])

        XCTAssertEqual(result, [recall])
    }
}

/// Always fails — used to prove a swipe is durably queued before any
/// network attempt succeeds (or is even reachable).
private struct NeverSucceedingReviewSyncing: ReviewSyncing {
    struct Failure: Error {}
    func recordReview(_ review: PendingReview) async throws {
        throw Failure()
    }
}
