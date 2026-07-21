import Foundation

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var collections: [WordCollection]

    init(collections: [WordCollection] = MockData.collections) {
        self.collections = collections
    }

    /// No-op until Phase 3 wires a real Supabase-backed implementation.
    /// Exists now so `RootView`'s `.task { await store.loadFromRemote() }`
    /// wiring never has to change shape later.
    func loadFromRemote() async {}

    func add(_ collection: WordCollection) {
        collections.append(collection)
    }

    func rename(_ collectionId: UUID, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        collections[index].name = name
    }

    func delete(_ collectionId: UUID) {
        collections.removeAll { $0.id == collectionId }
    }
}
