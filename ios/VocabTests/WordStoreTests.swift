import XCTest
@testable import Vocab

@MainActor
final class WordStoreTests: XCTestCase {
    private let collectionId = UUID()

    private func makeWord(status: WordStatus = .new, knowCount: Int = 0) -> Word {
        Word(collectionId: collectionId, term: "term", translation: "translation", status: status, knowCount: knowCount)
    }

    private func makeStore(words: [Word] = MockData.words) -> WordStore {
        WordStore(words: words, database: .makeInMemory())
    }

    func testDefaultInitSeedsFromMockData() {
        let store = makeStore()
        XCTAssertEqual(store.words.map(\.id), MockData.words.map(\.id))
    }

    func testWordsInFiltersByCollection() {
        let inCollection = makeWord()
        let other = Word(collectionId: UUID(), term: "x", translation: "y")
        let store = makeStore(words: [inCollection, other])

        XCTAssertEqual(store.words(in: collectionId).map(\.id), [inCollection.id])
    }

    func testAddAppendsWord() {
        let store = makeStore(words: [])
        let word = makeWord()

        store.add(word)

        XCTAssertEqual(store.words, [word])
    }

    func testDeleteRemovesOnlyTheMatchingWord() {
        let target = makeWord()
        let other = makeWord()
        let store = makeStore(words: [target, other])

        store.delete(target.id)

        XCTAssertEqual(store.words.map(\.id), [other.id])
    }

    func testApplySwipeUpdatesTheStoredWordOptimistically() {
        let word = makeWord(status: .new, knowCount: 0)
        let store = makeStore(words: [word])

        let outcome = store.applySwipe(.know, to: word.id, now: Date())

        XCTAssertNotNil(outcome)
        XCTAssertEqual(store.word(word.id)?.knowCount, 1)
    }

    func testApplySwipeOnUnknownWordIdIsANoOp() {
        let store = makeStore(words: [])
        let outcome = store.applySwipe(.know, to: UUID(), now: Date())
        XCTAssertNil(outcome)
    }

    func testSetStatusToLearntResetsSchedulingFieldsToSensibleDefaults() {
        let word = makeWord(status: .new, knowCount: 2)
        let store = makeStore(words: [word])

        store.setStatus(.learnt, for: word.id, now: Date(timeIntervalSince1970: 1_700_000_000))

        let updated = store.word(word.id)!
        XCTAssertEqual(updated.status, .learnt)
        XCTAssertEqual(updated.intervalStep, 0)
        XCTAssertNotNil(updated.dueAt)
    }

    func testSetStatusToLearningResetsBackToDeckDefaults() {
        let word = makeWord(status: .learnt, knowCount: 3)
        let store = makeStore(words: [word])

        store.setStatus(.learning, for: word.id)

        let updated = store.word(word.id)!
        XCTAssertEqual(updated.status, .learning)
        XCTAssertEqual(updated.knowCount, 0)
        XCTAssertNil(updated.dueAt)
    }

    // MARK: - Outbox: applySwipe enqueues a durable pending_reviews row

    func testApplySwipeEnqueuesAPendingReviewSurvivingRestart() {
        let database = AppDatabase.makeInMemory()
        let word = makeWord(status: .new, knowCount: 0)
        let store = WordStore(words: [word], database: database, reviewSyncing: NeverSucceedingReviewSyncing())

        let outcome = store.applySwipe(.know, to: word.id, now: Date(timeIntervalSince1970: 1_700_000_000))

        let pending = try! database.fetchPendingReviews()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, outcome?.log.id)
        XCTAssertEqual(pending.first?.wordId, word.id)
        XCTAssertEqual(pending.first?.knowCountAfter, 1)
    }

    // MARK: - loadFromRemote reconciliation

    func testReconcileKeepsLocalWordWhenAPendingReviewExistsForIt() {
        var local = makeWord(status: .learning, knowCount: 2)
        local.updatedAt = Date(timeIntervalSince1970: 1_000)
        var remote = local
        remote.knowCount = 0 // stale server copy, predates the queued swipe
        remote.updatedAt = Date(timeIntervalSince1970: 2_000) // even "newer" by clock

        let reconciled = WordStore.reconcile(remote: [remote], local: [local], pendingWordIds: [local.id])

        XCTAssertEqual(reconciled.first?.knowCount, 2, "a pending outbox entry means local is ahead regardless of updatedAt")
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

    // MARK: - applyRealtimeChange (single-row upsert/delete)

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
}

/// Always fails — used to prove a swipe is durably queued before any
/// network attempt succeeds (or is even reachable).
private struct NeverSucceedingReviewSyncing: ReviewSyncing {
    struct Failure: Error {}
    func recordReview(_ review: PendingReview) async throws {
        throw Failure()
    }
}
