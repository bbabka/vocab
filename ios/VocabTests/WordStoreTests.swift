import XCTest
@testable import Vocab

@MainActor
final class WordStoreTests: XCTestCase {
    private let collectionId = UUID()

    private func makeWord(status: WordStatus = .new, knowCount: Int = 0) -> Word {
        Word(collectionId: collectionId, term: "term", translation: "translation", status: status, knowCount: knowCount)
    }

    func testDefaultInitSeedsFromMockData() {
        let store = WordStore()
        XCTAssertEqual(store.words.map(\.id), MockData.words.map(\.id))
    }

    func testWordsInFiltersByCollection() {
        let inCollection = makeWord()
        let other = Word(collectionId: UUID(), term: "x", translation: "y")
        let store = WordStore(words: [inCollection, other])

        XCTAssertEqual(store.words(in: collectionId).map(\.id), [inCollection.id])
    }

    func testAddAppendsWord() {
        let store = WordStore(words: [])
        let word = makeWord()

        store.add(word)

        XCTAssertEqual(store.words, [word])
    }

    func testDeleteRemovesOnlyTheMatchingWord() {
        let target = makeWord()
        let other = makeWord()
        let store = WordStore(words: [target, other])

        store.delete(target.id)

        XCTAssertEqual(store.words.map(\.id), [other.id])
    }

    func testApplySwipeUpdatesTheStoredWordOptimistically() {
        let word = makeWord(status: .new, knowCount: 0)
        let store = WordStore(words: [word])

        let outcome = store.applySwipe(.know, to: word.id, now: Date())

        XCTAssertNotNil(outcome)
        XCTAssertEqual(store.word(word.id)?.knowCount, 1)
    }

    func testApplySwipeOnUnknownWordIdIsANoOp() {
        let store = WordStore(words: [])
        let outcome = store.applySwipe(.know, to: UUID(), now: Date())
        XCTAssertNil(outcome)
    }

    func testSetStatusToLearntResetsSchedulingFieldsToSensibleDefaults() {
        let word = makeWord(status: .new, knowCount: 2)
        let store = WordStore(words: [word])

        store.setStatus(.learnt, for: word.id, now: Date(timeIntervalSince1970: 1_700_000_000))

        let updated = store.word(word.id)!
        XCTAssertEqual(updated.status, .learnt)
        XCTAssertEqual(updated.intervalStep, 0)
        XCTAssertNotNil(updated.dueAt)
    }

    func testSetStatusToLearningResetsBackToDeckDefaults() {
        let word = makeWord(status: .learnt, knowCount: 3)
        let store = WordStore(words: [word])

        store.setStatus(.learning, for: word.id)

        let updated = store.word(word.id)!
        XCTAssertEqual(updated.status, .learning)
        XCTAssertEqual(updated.knowCount, 0)
        XCTAssertNil(updated.dueAt)
    }
}
