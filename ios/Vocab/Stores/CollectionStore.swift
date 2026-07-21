import Foundation
import Supabase

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var collections: [WordCollection]
    @Published var syncError: String?

    private let client: SupabaseClient

    init(collections: [WordCollection] = MockData.collections, client: SupabaseClient = SupabaseClientProvider.shared) {
        self.collections = collections
        self.client = client
    }

    /// Replaces local state with the signed-in user's rows; RLS scopes the
    /// fetch automatically.
    func loadFromRemote() async {
        do {
            collections = try await CollectionAPI.fetchAll()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Optimistic add: appends locally first, then persists in the
    /// background. Rolls back on failure since this is an infrequent,
    /// explicit user action (not a swipe needing instant local feedback).
    func add(_ collection: WordCollection) {
        collections.append(collection)
        Task {
            do {
                try await CollectionAPI.insert(collection)
            } catch {
                collections.removeAll { $0.id == collection.id }
                syncError = error.localizedDescription
            }
        }
    }

    func rename(_ collectionId: UUID, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let previous = collections[index]
        collections[index].name = name
        let updated = collections[index]
        Task {
            do {
                try await CollectionAPI.update(updated)
            } catch {
                if let currentIndex = collections.firstIndex(where: { $0.id == collectionId }) {
                    collections[currentIndex] = previous
                }
                syncError = error.localizedDescription
            }
        }
    }

    func delete(_ collectionId: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let removed = collections.remove(at: index)
        Task {
            do {
                try await CollectionAPI.delete(collectionId)
            } catch {
                collections.insert(removed, at: min(index, collections.count))
                syncError = error.localizedDescription
            }
        }
    }
}
