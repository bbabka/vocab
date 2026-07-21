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
}
