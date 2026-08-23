import Foundation
import Supabase

@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var words: [Word]
    @Published private(set) var wordProgress: [WordProgress]
    @Published var syncError: String?

    private let client: SupabaseClient
    private let database: AppDatabase
    private let reviewSyncing: ReviewSyncing
    private var isDraining = false

    init(
        words: [Word] = MockData.words,
        wordProgress: [WordProgress] = MockData.wordProgress,
        client: SupabaseClient = SupabaseClientProvider.shared,
        database: AppDatabase = .shared,
        reviewSyncing: ReviewSyncing = SupabaseReviewSyncing()
    ) {
        self.words = words
        self.wordProgress = wordProgress
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
    ///
    /// Fetches `word_progress` alongside `words` — Recall Layer (v2) moved
    /// all scheduling state there, so a word without its progress rows
    /// isn't practiceable in either direction.
    ///
    /// The two fetches run in **independent** do/catch blocks, not one
    /// shared block: an earlier version awaited them sequentially inside a
    /// single `do`, so a failure fetching `word_progress` (e.g. the table
    /// briefly not existing on the backend yet) threw before `words` was
    /// ever reconciled from its already-successful fetch — discarding a
    /// good result because of an unrelated failure, and falling all the way
    /// back to the local cache for both. Keeping them independent means a
    /// failure in one can't take down the other.
    ///
    /// Both requests are kicked off together via `async let` (matching
    /// `ReviewStore.loadFromRemote`'s pattern) so this costs one round
    /// trip's worth of latency, not two back-to-back — `async let` starts
    /// the child task at the point it's declared, and awaiting each inside
    /// its own `do` preserves the independent-failure behavior above.
    func loadFromRemote() async {
        let pending = (try? database.fetchPendingReviews()) ?? []

        // Loaded unconditionally, before either fetch: on a cold launch,
        // `words`/`wordProgress` are still each store's placeholder
        // `MockData` default (see `init`), not this device's real last-known
        // state. Reconciling straight against that placeholder means no key
        // ever matches a real row, so the pending-outbox protection below
        // never engages and a fresh remote fetch clobbers any not-yet-synced
        // local progress outright. Seeding from the GRDB mirror first makes
        // `local` the real previous state before reconciliation runs.
        if let cachedWords = try? database.fetchWords() {
            words = cachedWords
        }
        if let cachedProgress = try? database.fetchWordProgress() {
            wordProgress = cachedProgress
        }

        async let remoteWords = WordAPI.fetchAll()
        async let remoteProgress = WordProgressAPI.fetchAll()

        do {
            let remote = try await remoteWords
            let pendingWordIds = Set(pending.map(\.wordId))
            words = Self.reconcile(remote: remote, local: words, pendingWordIds: pendingWordIds)
            try? database.replaceWords(words)
        } catch {
            syncError = error.localizedDescription
        }

        do {
            let remote = try await remoteProgress
            let pendingProgressKeys = Set(pending.map { WordProgressKey(wordId: $0.wordId, direction: $0.direction) })
            wordProgress = Self.reconcileProgress(remote: remote, local: wordProgress, pendingKeys: pendingProgressKeys)
            try? database.replaceWordProgress(wordProgress)
        } catch {
            syncError = [syncError, error.localizedDescription].compactMap { $0 }.joined(separator: "; ")
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

    /// Same shape as `reconcile`, keyed by `(wordId, direction)` rather than
    /// a single id — that's `WordProgress`'s real identity from the
    /// client's point of view (see its doc comment).
    static func reconcileProgress(remote: [WordProgress], local: [WordProgress], pendingKeys: Set<WordProgressKey>) -> [WordProgress] {
        Reconciler.merge(remote: remote, local: local, key: \.key, pendingKeys: pendingKeys) { local, remote, isPending in
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
            wordProgress.removeAll { $0.wordId == id }
            try? database.deleteWord(id)
            try? database.deleteWordProgress(forWordId: id)
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

    /// Applies one incoming `postgres_changes` row for `word_progress` —
    /// same reconciliation rules as `applyRealtimeChange`, keyed by
    /// `(wordId, direction)`. Fires for both the initial `recognize` row a
    /// new word gets and the `recall` row the unlock trigger creates.
    func applyRealtimeProgressChange(_ change: AnyAction) {
        let pending = (try? database.fetchPendingReviews()) ?? []
        let pendingKeys = Set(pending.map { WordProgressKey(wordId: $0.wordId, direction: $0.direction) })
        switch change {
        case .insert(let insert):
            applyIncomingProgress(insert, pendingKeys: pendingKeys)
        case .update(let update):
            applyIncomingProgress(update, pendingKeys: pendingKeys)
        case .delete(let delete):
            guard let wordIdString = delete.oldRecord["word_id"]?.stringValue,
                  let wordId = UUID(uuidString: wordIdString),
                  let directionString = delete.oldRecord["direction"]?.stringValue,
                  let direction = PracticeDirection(rawValue: directionString) else { return }
            let key = WordProgressKey(wordId: wordId, direction: direction)
            wordProgress = Self.applyingRealtimeProgressDelete(key, from: wordProgress)
        }
    }

    private func applyIncomingProgress(_ action: some HasRecord, pendingKeys: Set<WordProgressKey>) {
        guard let remote = try? action.decodeRecord(as: WordProgress.self, decoder: SupabaseClientProvider.payloadDecoder) else { return }
        guard let updated = Self.applyingRealtimeProgressUpsert(remote, into: wordProgress, pendingKeys: pendingKeys) else { return }
        wordProgress = updated
        try? database.upsertWordProgress(remote)
    }

    /// Same pending/last-write-wins rules as `reconcile`, but as an upsert
    /// into the existing array rather than a wholesale replace — see
    /// `Reconciler.upsertOne` for why `Reconciler.merge` isn't reusable
    /// as-is for a single incoming row. Returns `nil` when the incoming row
    /// shouldn't change local state (pending outbox entry, or a stale/
    /// out-of-order row older than what's already there).
    static func applyingRealtimeUpsert(_ remote: Word, into words: [Word], pendingWordIds: Set<UUID>) -> [Word]? {
        Reconciler.upsertOne(remote, into: words, key: \.id, pendingKeys: pendingWordIds, updatedAt: \.updatedAt)
    }

    static func applyingRealtimeDelete(_ id: UUID, from words: [Word]) -> [Word] {
        words.filter { $0.id != id }
    }

    static func applyingRealtimeProgressUpsert(_ remote: WordProgress, into progress: [WordProgress], pendingKeys: Set<WordProgressKey>) -> [WordProgress]? {
        Reconciler.upsertOne(remote, into: progress, key: \.key, pendingKeys: pendingKeys, updatedAt: \.updatedAt)
    }

    static func applyingRealtimeProgressDelete(_ key: WordProgressKey, from progress: [WordProgress]) -> [WordProgress] {
        progress.filter { $0.key != key }
    }

    func words(in collectionId: UUID) -> [Word] {
        words.filter { $0.collectionId == collectionId }
    }

    func word(_ id: UUID) -> Word? {
        words.first { $0.id == id }
    }

    /// The "headline" progress views read for library filters, stats counts,
    /// and status badges — see the brief's "What 'learnt' means at the word
    /// level". `nil` only in the brief window before a word's progress rows
    /// have synced (see `add(_:)`'s optimistic-append comment).
    func recognizeProgress(for wordId: UUID) -> WordProgress? {
        progress(for: wordId, direction: .recognize)
    }

    /// Clears in-memory state on sign-out (see `CollectionStore.reset()` for
    /// why this matters). Does not touch the outbox or local mirror —
    /// `AuthStore.signOut()` refuses to run at all while `pending_reviews`
    /// is non-empty, so by the time this is called there's nothing left to
    /// lose, and `AppDatabase.wipe()` handles clearing the mirror itself.
    func reset() {
        words = []
        wordProgress = []
        syncError = nil
    }

    /// Optimistic add: infrequent, explicit user action, so it rolls back on
    /// a persistence failure rather than trusting local state unconditionally
    /// (unlike a practice swipe, there's no "instant feedback during a fast
    /// session" pressure here). Adding a word is not covered by the offline
    /// outbox (that's swipes only) — it still requires connectivity.
    ///
    /// Also optimistically appends the `recognize` progress row a DB trigger
    /// creates server-side on insert, so the word is immediately
    /// practiceable without waiting on a fetch/realtime round-trip. The
    /// server assigns its own `id` for that row; the optimistic copy here
    /// only needs to match on `(wordId, direction)` for later reconciliation
    /// to replace it correctly (see `WordProgress`'s doc comment).
    func add(_ word: Word) {
        words.append(word)
        let initialProgress = WordProgress(wordId: word.id, direction: .recognize, updatedAt: word.updatedAt)
        wordProgress.append(initialProgress)
        Task {
            do {
                try await WordAPI.insert(word)
                try? database.upsertWord(word)
                try? database.upsertWordProgress(initialProgress)
            } catch {
                words.removeAll { $0.id == word.id }
                wordProgress.removeAll { $0.wordId == word.id }
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
        let removedProgress = wordProgress.filter { $0.wordId == wordId }
        wordProgress.removeAll { $0.wordId == wordId }
        Task {
            do {
                try await WordAPI.delete(wordId)
                try? database.deleteWord(wordId)
                try? database.deleteWordProgress(forWordId: wordId)
                // A queued review for this word can never apply once it's
                // gone — drop it rather than let drainOutbox() keep hitting
                // record_review's "word not found" error on every retry.
                try? database.deletePendingReviews(forWordId: wordId)
            } catch {
                words.insert(removed, at: min(index, words.count))
                wordProgress.append(contentsOf: removedProgress)
                syncError = error.localizedDescription
            }
        }
    }

    /// Assembles a practice batch from the current in-memory word set for
    /// `collectionIds` and `direction`, or across all collections when
    /// `collectionIds` is nil or empty (the brief's "All" option).
    func assembleBatch(collectionIds: Set<UUID>?, direction: PracticeDirection, batchSize: Int, now: Date = Date()) -> [PracticeCard] {
        let pool = pool(for: collectionIds)
        return ReviewScheduler.assembleBatch(from: pool, progress: progressPool(for: pool), direction: direction, batchSize: batchSize, now: now)
    }

    func isFullyRetired(collectionIds: Set<UUID>?, direction: PracticeDirection, now: Date = Date()) -> Bool {
        let pool = pool(for: collectionIds)
        return ReviewScheduler.isFullyRetired(progressPool(for: pool), words: pool, direction: direction, now: now)
    }

    private func pool(for collectionIds: Set<UUID>?) -> [Word] {
        guard let collectionIds, !collectionIds.isEmpty else { return words }
        return words.filter { collectionIds.contains($0.collectionId) }
    }

    private func progressPool(for words: [Word]) -> [WordProgress] {
        let wordIds = Set(words.map(\.id))
        return wordProgress.filter { wordIds.contains($0.wordId) }
    }

    /// The "headline" status views read for library filters, stats counts,
    /// and status badges — see the brief's "What 'learnt' means at the word
    /// level". A single shared source instead of each view rebuilding its
    /// own `wordId → status` dictionary from `wordProgress`.
    var recognizeStatusByWordId: [UUID: WordStatus] {
        Dictionary(uniqueKeysWithValues: wordProgress
            .filter { $0.direction == .recognize }
            .map { ($0.wordId, $0.status) })
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
    func applySwipe(_ swipe: ReviewResult, to wordId: UUID, direction: PracticeDirection, now: Date = Date()) -> ReviewScheduler.Outcome? {
        // `entry.status != .retired` guards against `ReviewScheduler.apply`'s
        // precondition: the same card can be committed twice in quick
        // succession (a fast double-swipe/double-skip before the UI catches
        // up), or a Realtime update from another device can retire this
        // word between batch assembly and this swipe landing. Either way,
        // there's nothing sensible left to apply — no-op rather than crash.
        guard let entry = progress(for: wordId, direction: direction), entry.status != .retired else { return nil }
        let outcome = ReviewScheduler.apply(swipe, to: entry, now: now)
        updateProgress(outcome.progress)
        // Explicit do/catch, not `try?`: if the local GRDB write itself
        // fails (disk full, migration mismatch), the swipe would otherwise
        // be lost silently — never queued, never synced, no trace anywhere.
        // Surfacing it via `syncError` is the best we can do for a failure
        // this deep in the local storage layer.
        do {
            try database.upsertWordProgress(outcome.progress)
            try database.enqueuePendingReview(PendingReview(outcome: outcome))
        } catch {
            syncError = error.localizedDescription
        }
        Task { await drainOutbox() }
        return outcome
    }

    private func progress(for wordId: UUID, direction: PracticeDirection) -> WordProgress? {
        wordProgress.first { $0.wordId == wordId && $0.direction == direction }
    }

    private func updateProgress(_ entry: WordProgress) {
        guard let index = wordProgress.firstIndex(where: { $0.key == entry.key }) else { return }
        wordProgress[index] = entry
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

    /// Manual override from Word Detail: force `recognize`'s status,
    /// resetting the scheduling fields to sensible defaults for that status
    /// per the brief. Always targets `recognize`, never `recall` — the
    /// brief treats `recognize` as the word's "headline" state, which is
    /// what a status override in Word Detail colloquially means.
    ///
    /// Writes through `WordProgressAPI.update`, not `record_review` — a
    /// second legitimate write path onto `word_progress`, deliberately not
    /// funneled through the RPC. The DB-side unlock trigger fires on
    /// `word_progress` itself regardless of which path wrote to it, so a
    /// word manually forced to `learnt` here still unlocks `recall`
    /// correctly (see the `word_progress_unlock_recall` migration).
    func setStatus(_ status: WordStatus, for wordId: UUID, now: Date = Date()) {
        let direction = PracticeDirection.recognize
        guard var entry = progress(for: wordId, direction: direction) else { return }
        let previous = entry
        switch status {
        case .new:
            entry.knowCount = 0
            entry.intervalStep = 0
            entry.dueAt = nil
        case .learning:
            entry.knowCount = 0
            entry.intervalStep = 0
            entry.dueAt = nil
        case .learnt:
            entry.intervalStep = 0
            entry.dueAt = now.addingTimeInterval(TimeInterval(SchedulingConstants.resurfaceLadderDays[0]) * 86400)
        case .retired:
            entry.dueAt = nil
        }
        entry.status = status
        entry.updatedAt = now
        updateProgress(entry)
        Task {
            do {
                try await WordProgressAPI.update(entry)
                try? database.upsertWordProgress(entry)
            } catch {
                updateProgress(previous)
                syncError = error.localizedDescription
            }
        }
    }
}
