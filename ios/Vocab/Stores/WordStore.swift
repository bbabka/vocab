import Foundation
import Supabase

@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var words: [Word]
    @Published var syncError: String?

    private let client: SupabaseClient
    private let database: AppDatabase
    private let reviewSyncing: ReviewSyncing
    private var isDraining = false

    init(
        words: [Word] = MockData.words,
        client: SupabaseClient = SupabaseClientProvider.shared,
        database: AppDatabase = .shared,
        reviewSyncing: ReviewSyncing = SupabaseReviewSyncing()
    ) {
        self.words = words
        self.client = client
        self.database = database
        self.reviewSyncing = reviewSyncing
    }

    /// Replaces local state with the signed-in user's rows; RLS scopes the
    /// fetch automatically. Reconciles against the outbox and the local
    /// mirror rather than blindly overwriting, then re-mirrors the result —
    /// this is what a Realtime `postgres_changes` row will also run through
    /// once Phase 5 wires it up. Falls back to the local mirror when the
    /// fetch itself fails (offline).
    func loadFromRemote() async {
        do {
            let remote = try await WordAPI.fetchAll()
            let pendingWordIds = Set((try? database.fetchPendingReviews().map(\.wordId)) ?? [])
            words = Self.reconcile(remote: remote, local: words, pendingWordIds: pendingWordIds)
            try? database.replaceWords(words)
        } catch {
            if let cached = try? database.fetchWords() {
                words = cached
            }
            syncError = error.localizedDescription
        }
    }

    /// Merges a freshly fetched remote row set over local state: if a
    /// `pending_reviews` entry exists for a word, local optimistic state is
    /// ahead of the server and wins outright; otherwise it's last-write-wins
    /// by `updatedAt`, so a local edit that hasn't round-tripped yet doesn't
    /// get clobbered by a stale-in-flight fetch.
    static func reconcile(remote: [Word], local: [Word], pendingWordIds: Set<UUID>) -> [Word] {
        Reconciler.merge(remote: remote, local: local, key: \.id, pendingKeys: pendingWordIds) { local, remote, isPending in
            if isPending { return local }
            return local.updatedAt > remote.updatedAt ? local : remote
        }
    }

    /// Applies one incoming `postgres_changes` row for `words`. Decodes with
    /// the same rules PostgREST responses use, then defers to the pure
    /// `applyingRealtimeUpsert`/`applyingRealtimeDelete` below for the actual
    /// merge decision — kept separate from this method (which also touches
    /// the GRDB mirror) so the merge logic itself stays unit-testable
    /// without needing to construct a real `AnyAction` (the SDK's action
    /// types have no public initializer).
    func applyRealtimeChange(_ change: AnyAction) {
        let pendingWordIds = Set((try? database.fetchPendingReviews().map(\.wordId)) ?? [])
        switch change {
        case .insert(let insert):
            applyIncomingWord(insert, pendingWordIds: pendingWordIds)
        case .update(let update):
            applyIncomingWord(update, pendingWordIds: pendingWordIds)
        case .delete(let delete):
            guard let id = delete.oldRecord["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { return }
            words = Self.applyingRealtimeDelete(id, from: words)
            try? database.deleteWord(id)
            // Mirrors `delete(_:)`: a queued review for a word deleted on
            // another device can never apply once it syncs.
            try? database.deletePendingReviews(forWordId: id)
        }
    }

    private func applyIncomingWord(_ action: some HasRecord, pendingWordIds: Set<UUID>) {
        guard let remote = try? action.decodeRecord(as: Word.self, decoder: SupabaseClientProvider.payloadDecoder) else { return }
        guard let updated = Self.applyingRealtimeUpsert(remote, into: words, pendingWordIds: pendingWordIds) else { return }
        words = updated
        try? database.upsertWord(remote)
    }

    /// Same pending/last-write-wins rules as `reconcile`, but as an upsert
    /// into the existing array rather than a wholesale replace — a single
    /// incoming row must not drop every other word not present in this one
    /// remote row, which is what `Reconciler.merge` would do if handed a
    /// one-element `remote` array. Returns `nil` when the incoming row
    /// shouldn't change local state (pending outbox entry, or a stale/
    /// out-of-order row older than what's already there).
    static func applyingRealtimeUpsert(_ remote: Word, into words: [Word], pendingWordIds: Set<UUID>) -> [Word]? {
        guard !pendingWordIds.contains(remote.id) else { return nil }
        guard let index = words.firstIndex(where: { $0.id == remote.id }) else {
            return words + [remote]
        }
        guard remote.updatedAt >= words[index].updatedAt else { return nil }
        var updated = words
        updated[index] = remote
        return updated
    }

    static func applyingRealtimeDelete(_ id: UUID, from words: [Word]) -> [Word] {
        words.filter { $0.id != id }
    }

    func words(in collectionId: UUID) -> [Word] {
        words.filter { $0.collectionId == collectionId }
    }

    func word(_ id: UUID) -> Word? {
        words.first { $0.id == id }
    }

    /// Clears in-memory state on sign-out (see `CollectionStore.reset()` for
    /// why this matters). Does not touch the outbox or local mirror —
    /// `AuthStore.signOut()` refuses to run at all while `pending_reviews`
    /// is non-empty, so by the time this is called there's nothing left to
    /// lose, and `AppDatabase.wipe()` handles clearing the mirror itself.
    func reset() {
        words = []
        syncError = nil
    }

    /// Optimistic add: infrequent, explicit user action, so it rolls back on
    /// a persistence failure rather than trusting local state unconditionally
    /// (unlike a practice swipe, there's no "instant feedback during a fast
    /// session" pressure here). Adding a word is not covered by the offline
    /// outbox (that's swipes only) — it still requires connectivity.
    func add(_ word: Word) {
        words.append(word)
        Task {
            do {
                try await WordAPI.insert(word)
                try? database.upsertWord(word)
            } catch {
                words.removeAll { $0.id == word.id }
                syncError = error.localizedDescription
            }
        }
    }

    /// Local-only. Backs every keystroke of `WordDetailView`'s bindings —
    /// persisting here would fire a network request per character. The
    /// screen writes the final draft through once, via `persist(_:)`, when
    /// the user navigates away.
    func update(_ word: Word) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
    }

    /// Write-through for `WordDetailView`'s `onDisappear`: persists whatever
    /// `update(_:)` has accumulated locally for `wordId` since the screen
    /// appeared. Rolls back to `previous` on failure.
    func persist(_ wordId: UUID, previous: Word) {
        guard let current = word(wordId), current != previous else { return }
        Task {
            do {
                try await WordAPI.update(current)
                try? database.upsertWord(current)
            } catch {
                if let index = words.firstIndex(where: { $0.id == wordId }) {
                    words[index] = previous
                }
                syncError = error.localizedDescription
            }
        }
    }

    func delete(_ wordId: UUID) {
        guard let index = words.firstIndex(where: { $0.id == wordId }) else { return }
        let removed = words.remove(at: index)
        Task {
            do {
                try await WordAPI.delete(wordId)
                try? database.deleteWord(wordId)
                // A queued review for this word can never apply once it's
                // gone — drop it rather than let drainOutbox() keep hitting
                // record_review's "word not found" error on every retry.
                try? database.deletePendingReviews(forWordId: wordId)
            } catch {
                words.insert(removed, at: min(index, words.count))
                syncError = error.localizedDescription
            }
        }
    }

    /// Assembles a practice batch from the current in-memory word set for
    /// `collectionId`, or across all collections when `collectionId` is nil
    /// (the brief's "All" option).
    func assembleBatch(collectionId: UUID?, batchSize: Int, now: Date = Date()) -> [Word] {
        let pool = collectionId.map(words(in:)) ?? words
        return ReviewScheduler.assembleBatch(from: pool, batchSize: batchSize, now: now)
    }

    func isFullyRetired(collectionId: UUID?, now: Date = Date()) -> Bool {
        let pool = collectionId.map(words(in:)) ?? words
        return ReviewScheduler.isFullyRetired(pool, now: now)
    }

    /// Applies one swipe: runs the pure `ReviewScheduler`, writes the
    /// resulting word state back into `words` and the local GRDB mirror
    /// optimistically, and returns the outcome so the caller can hand the
    /// log/activity-date to `ReviewStore`. Deliberately does not touch
    /// `ReviewStore` itself — stores stay independent, matching Reader's
    /// pattern of stores that don't reference each other.
    ///
    /// Persistence goes through the outbox, not a direct network call: the
    /// swipe is queued as a `pending_reviews` row (durable — it survives an
    /// app kill) and an opportunistic drain is kicked off immediately after.
    /// If that drain succeeds, the swipe is synced within moments of being
    /// taken; if it's offline, the row just waits for the next drain trigger
    /// (launch or reconnect). Either way, the swipe itself never blocks or
    /// rolls back on a sync failure — matching the brief's "register
    /// instantly and sync in the background."
    @discardableResult
    func applySwipe(_ swipe: ReviewResult, to wordId: UUID, now: Date = Date()) -> ReviewScheduler.Outcome? {
        guard let word = word(wordId) else { return nil }
        let outcome = ReviewScheduler.apply(swipe, to: word, now: now)
        update(outcome.word)
        // Explicit do/catch, not `try?`: if the local GRDB write itself
        // fails (disk full, migration mismatch), the swipe would otherwise
        // be lost silently — never queued, never synced, no trace anywhere.
        // Surfacing it via `syncError` is the best we can do for a failure
        // this deep in the local storage layer.
        do {
            try database.upsertWord(outcome.word)
            try database.enqueuePendingReview(PendingReview(outcome: outcome))
        } catch {
            syncError = error.localizedDescription
        }
        Task { await drainOutbox() }
        return outcome
    }

    /// Replays queued swipes strictly in `clientReviewedAt` order, one at a
    /// time, awaited sequentially — the same word can recur across multiple
    /// queued offline swipes, so order matters beyond what the RPC's
    /// idempotent insert alone protects. Re-fetches the pending list before
    /// every row (rather than looping over one upfront snapshot) so a swipe
    /// queued by another call while this drain is mid-flight — which sees
    /// `isDraining` already `true` and no-ops immediately — still gets
    /// picked up by this same drain once it reaches that point, instead of
    /// being stranded until some unrelated later trigger.
    ///
    /// A transient failure halts the drain right there (no skip-ahead) and
    /// leaves the rest queued for the next trigger (app launch or
    /// reconnect). A *permanent* failure — `record_review`'s "word not
    /// found" error, meaning the word was deleted before this review synced
    /// — is different: retrying it can never succeed, so that row is
    /// dropped and the drain continues past it rather than jamming every
    /// other queued review behind it forever.
    ///
    /// A concurrent call to this method while one is already running is a
    /// no-op, since the RPC being idempotent doesn't mean it's free to call
    /// twice.
    func drainOutbox() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while true {
            guard let pending = try? database.fetchPendingReviews(), let review = pending.first else { return }
            do {
                try await reviewSyncing.recordReview(review)
                try? database.deletePendingReview(review.id)
            } catch {
                if PendingReviewAPI.isWordNotFoundError(error) {
                    try? database.deletePendingReview(review.id)
                    continue
                }
                try? database.markPendingReviewFailed(review.id, error: error.localizedDescription)
                syncError = error.localizedDescription
                return
            }
        }
    }

    /// Manual override from Word Detail: force a status, resetting the
    /// scheduling fields to sensible defaults for that status per the brief.
    func setStatus(_ status: WordStatus, for wordId: UUID, now: Date = Date()) {
        guard var word = word(wordId) else { return }
        let previous = word
        switch status {
        case .new:
            word.knowCount = 0
            word.intervalStep = 0
            word.dueAt = nil
        case .learning:
            word.knowCount = 0
            word.intervalStep = 0
            word.dueAt = nil
        case .learnt:
            word.intervalStep = 0
            word.dueAt = now.addingTimeInterval(TimeInterval(SchedulingConstants.resurfaceLadderDays[0]) * 86400)
        case .retired:
            word.dueAt = nil
        }
        word.status = status
        word.updatedAt = now
        update(word)
        Task {
            do {
                try await WordAPI.update(word)
                try? database.upsertWord(word)
            } catch {
                update(previous)
                syncError = error.localizedDescription
            }
        }
    }
}
