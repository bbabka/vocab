import XCTest
@testable import Vocab

@MainActor
final class CollectionStoreTests: XCTestCase {
    func testDefaultInitSeedsFromMockData() {
        let store = CollectionStore()
        XCTAssertEqual(store.collections.map(\.id), MockData.collections.map(\.id))
    }

    func testAddAppendsCollection() {
        let store = CollectionStore(collections: [])
        let collection = WordCollection(name: "French — Food", targetLanguage: "fr", nativeLanguage: "en")

        store.add(collection)

        XCTAssertEqual(store.collections, [collection])
    }

    func testRenameUpdatesOnlyTheMatchingCollection() {
        let target = WordCollection(name: "Old Name", targetLanguage: "es", nativeLanguage: "en")
        let other = WordCollection(name: "Unrelated", targetLanguage: "de", nativeLanguage: "en")
        let store = CollectionStore(collections: [target, other])

        store.rename(target.id, to: "New Name")

        XCTAssertEqual(store.collections.first(where: { $0.id == target.id })?.name, "New Name")
        XCTAssertEqual(store.collections.first(where: { $0.id == other.id })?.name, "Unrelated")
    }

    func testDeleteRemovesOnlyTheMatchingCollection() {
        let target = WordCollection(name: "To Delete", targetLanguage: "es", nativeLanguage: "en")
        let other = WordCollection(name: "Keep", targetLanguage: "de", nativeLanguage: "en")
        let store = CollectionStore(collections: [target, other])

        store.delete(target.id)

        XCTAssertEqual(store.collections, [other])
    }
}
