import Foundation

/// Shared shape behind `WordStore.reconcile` and `ReviewStore.reconcile`:
/// merge a freshly fetched `remote` row set with `local` state keyed by
/// `key`, letting `local` win outright wherever its key is in `pendingKeys`
/// (state the outbox hasn't synced yet, so `remote` can't be authoritative
/// for it), and otherwise letting `resolve` decide the winner — a wholesale
/// pick (last-write-wins) or a blend (e.g. `max` of two counts). Local-only
/// rows with a pending key that don't appear in `remote` at all are kept.
///
/// Written generically so Phase 5's Realtime handlers can reuse the same
/// merge instead of a third bespoke implementation.
enum Reconciler {
    static func merge<T, Key: Hashable>(
        remote: [T],
        local: [T],
        key: (T) -> Key,
        pendingKeys: Set<Key>,
        resolve: (_ local: T, _ remote: T, _ isPending: Bool) -> T
    ) -> [T] {
        let localByKey = Dictionary(uniqueKeysWithValues: local.map { (key($0), $0) })
        var merged = remote.map { remoteItem -> T in
            let itemKey = key(remoteItem)
            guard let localItem = localByKey[itemKey] else { return remoteItem }
            return resolve(localItem, remoteItem, pendingKeys.contains(itemKey))
        }

        let remoteKeys = Set(remote.map(key))
        for localItem in local where pendingKeys.contains(key(localItem)) && !remoteKeys.contains(key(localItem)) {
            merged.append(localItem)
        }
        return merged
    }

    /// Merges one incoming realtime row into an existing array — the
    /// single-row counterpart to `merge`, which assumes `remote` is the
    /// complete state and so isn't reusable as-is here (handing it a
    /// one-element `remote` array would drop every other item not present
    /// in that one row). Pending rows are left untouched (the outbox hasn't
    /// synced them yet, so `remote` can't be authoritative), new rows are
    /// appended, and existing ones are replaced by last-write-wins on
    /// `updatedAt`. Returns `nil` when the incoming row shouldn't change
    /// local state at all (pending, or a stale/out-of-order row older than
    /// what's already there).
    static func upsertOne<T, Key: Hashable>(
        _ remote: T,
        into items: [T],
        key: (T) -> Key,
        pendingKeys: Set<Key>,
        updatedAt: (T) -> Date
    ) -> [T]? {
        let remoteKey = key(remote)
        guard !pendingKeys.contains(remoteKey) else { return nil }
        guard let index = items.firstIndex(where: { key($0) == remoteKey }) else {
            return items + [remote]
        }
        guard updatedAt(remote) >= updatedAt(items[index]) else { return nil }
        var updated = items
        updated[index] = remote
        return updated
    }
}
