import Foundation
import Supabase

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var collections: [WordCollection]
    @Published var syncError: String?

    private let client: SupabaseClient
    private let database: AppDatabase

    init(
        collections: [WordCollection] = MockData.collections,
        client: SupabaseClient = SupabaseClientProvider.shared,
        database: AppDatabase = .shared
    ) {
        self.collections = collections
        self.client = client
        self.database = database
    }

    /// Replaces local state with the signed-in user's rows; RLS scopes the
    /// fetch automatically. Falls back to the local GRDB mirror when the
    /// fetch itself fails (offline) — collections have no write outbox (only
    /// swipes do), so this store's offline story is read-only.
    func loadFromRemote() async {
        do {
            collections = try await CollectionAPI.fetchAll()
            try? database.replaceCollections(collections)
        } catch {
            if let cached = try? database.fetchCollections() {
                collections = cached
            }
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
                try? database.upsertCollection(collection)
            } catch {
                collections.removeAll { $0.id == collection.id }
                syncError = error.localizedDescription
            }
        }
    }

    /// Applies one incoming `postgres_changes` row for `collections`.
    /// Unlike `WordStore`, there's no outbox and no `updatedAt` on
    /// `WordCollection` to arbitrate a conflict — collections' only local
    /// writes are `add`/`rename`/`delete`, which are optimistic-then-
    /// confirmed-online, so by the time a Realtime row for this id arrives,
    /// it reflects the current committed server state and can simply be
    /// applied wholesale.
    func applyRealtimeChange(_ change: AnyAction) {
        switch change {
        case .insert(let insert):
            applyIncomingCollection(insert)
        case .update(let update):
            applyIncomingCollection(update)
        case .delete(let delete):
            guard let id = delete.oldRecord["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { return }
            collections = Self.applyingRealtimeDelete(id, from: collections)
            try? database.deleteCollection(id)
            // Mirrors `delete(_:)`: SQLite doesn't cascade between the local
            // mirror tables, so a collection deleted on another device would
            // otherwise leave its words as orphans in `local_words`.
            try? database.deleteWords(forCollectionId: id)
        }
    }

    private func applyIncomingCollection(_ action: some HasRecord) {
        guard let remote = try? action.decodeRecord(as: WordCollection.self, decoder: SupabaseClientProvider.payloadDecoder) else { return }
        collections = Self.applyingRealtimeUpsert(remote, into: collections)
        try? database.upsertCollection(remote)
    }

    static func applyingRealtimeUpsert(_ remote: WordCollection, into collections: [WordCollection]) -> [WordCollection] {
        guard let index = collections.firstIndex(where: { $0.id == remote.id }) else {
            return collections + [remote]
        }
        var updated = collections
        updated[index] = remote
        return updated
    }

    static func applyingRealtimeDelete(_ id: UUID, from collections: [WordCollection]) -> [WordCollection] {
        collections.filter { $0.id != id }
    }

    func rename(_ collectionId: UUID, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let previous = collections[index]
        collections[index].name = name
        let updated = collections[index]
        Task {
            do {
                try await CollectionAPI.update(updated)
                try? database.upsertCollection(updated)
            } catch {
                if let currentIndex = collections.firstIndex(where: { $0.id == collectionId }) {
                    collections[currentIndex] = previous
                }
                syncError = error.localizedDescription
            }
        }
    }

    /// Clears in-memory state on sign-out. Without this, a `@StateObject`
    /// store (created once for the app's lifetime) would keep showing the
    /// previous account's collections to a newly signed-in different
    /// account for the brief window before `loadFromRemote()` completes —
    /// and would fall back to them again if that fetch failed, since they'd
    /// still look like valid cached data.
    func reset() {
        collections = []
        syncError = nil
    }

    func delete(_ collectionId: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let removed = collections.remove(at: index)
        Task {
            do {
                try await CollectionAPI.delete(collectionId)
                try? database.deleteCollection(collectionId)
                // SQLite enforces no cascade between the local mirror
                // tables — without this, the collection's words would
                // survive as orphans in `local_words` and could resurface
                // via WordStore's offline-read fallback.
                try? database.deleteWords(forCollectionId: collectionId)
            } catch {
                collections.insert(removed, at: min(index, collections.count))
                syncError = error.localizedDescription
            }
        }
    }
}
