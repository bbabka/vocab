import XCTest
@testable import Vocab

@MainActor
final class CollectionStoreTests: XCTestCase {
    private func makeStore(collections: [WordCollection] = MockData.collections) -> CollectionStore {
        CollectionStore(collections: collections, database: .makeInMemory())
    }

    func testDefaultInitSeedsFromMockData() {
        let store = makeStore()
        XCTAssertEqual(store.collections.map(\.id), MockData.collections.map(\.id))
    }

    func testAddAppendsCollection() {
        let store = makeStore(collections: [])
        let collection = WordCollection(name: "French — Food", targetLanguage: "fr", nativeLanguage: "en")

        store.add(collection)

        XCTAssertEqual(store.collections, [collection])
    }

    func testRenameUpdatesOnlyTheMatchingCollection() {
        let target = WordCollection(name: "Old Name", targetLanguage: "es", nativeLanguage: "en")
        let other = WordCollection(name: "Unrelated", targetLanguage: "de", nativeLanguage: "en")
        let store = makeStore(collections: [target, other])

        store.rename(target.id, to: "New Name")

        XCTAssertEqual(store.collections.first(where: { $0.id == target.id })?.name, "New Name")
        XCTAssertEqual(store.collections.first(where: { $0.id == other.id })?.name, "Unrelated")
    }

    func testDeleteRemovesOnlyTheMatchingCollection() {
        let target = WordCollection(name: "To Delete", targetLanguage: "es", nativeLanguage: "en")
        let other = WordCollection(name: "Keep", targetLanguage: "de", nativeLanguage: "en")
        let store = makeStore(collections: [target, other])

        store.delete(target.id)

        XCTAssertEqual(store.collections, [other])
    }

    // MARK: - applyRealtimeChange (single-row upsert/delete)

    func testRealtimeUpsertAppliesAnUpdateToAnExistingCollection() {
        let existing = WordCollection(name: "Old Name", targetLanguage: "es", nativeLanguage: "en")
        var renamed = existing
        renamed.name = "New Name"

        let result = CollectionStore.applyingRealtimeUpsert(renamed, into: [existing])

        XCTAssertEqual(result, [renamed])
    }

    func testRealtimeUpsertAppendsACollectionNotYetKnownLocally() {
        let remote = WordCollection(name: "New", targetLanguage: "de", nativeLanguage: "en")

        let result = CollectionStore.applyingRealtimeUpsert(remote, into: [])

        XCTAssertEqual(result, [remote])
    }

    func testRealtimeDeleteRemovesOnlyTheMatchingCollection() {
        let target = WordCollection(name: "To Delete", targetLanguage: "es", nativeLanguage: "en")
        let other = WordCollection(name: "Keep", targetLanguage: "de", nativeLanguage: "en")

        let result = CollectionStore.applyingRealtimeDelete(target.id, from: [target, other])

        XCTAssertEqual(result, [other])
    }
}
