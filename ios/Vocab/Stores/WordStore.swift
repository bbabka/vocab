import Foundation
import Supabase

@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var words: [Word]
    @Published var syncError: String?

    private let client: SupabaseClient

    init(words: [Word] = MockData.words, client: SupabaseClient = SupabaseClientProvider.shared) {
        self.words = words
        self.client = client
    }

    /// Replaces local state with the signed-in user's rows; RLS scopes the
    /// fetch automatically.
    func loadFromRemote() async {
        do {
            words = try await WordAPI.fetchAll()
        } catch {
            syncError = error.localizedDescription
        }
    }

    func words(in collectionId: UUID) -> [Word] {
        words.filter { $0.collectionId == collectionId }
    }

    func word(_ id: UUID) -> Word? {
        words.first { $0.id == id }
    }

    /// Optimistic add: infrequent, explicit user action, so it rolls back on
    /// a persistence failure rather than trusting local state unconditionally
    /// (unlike a practice swipe, there's no "instant feedback during a fast
    /// session" pressure here).
    func add(_ word: Word) {
        words.append(word)
        Task {
            do {
                try await WordAPI.insert(word)
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
    /// resulting word state back into `words` optimistically, and returns
    /// the outcome so the caller can hand the log/activity-date to
    /// `ReviewStore`. Deliberately does not touch `ReviewStore` itself —
    /// stores stay independent, matching Reader's pattern of stores that
    /// don't reference each other.
    ///
    /// Persists the updated word row in the background afterward,
    /// fire-and-forget — the brief's success criteria call for swipes to
    /// "register instantly and sync in the background," and Phase 3 has no
    /// offline outbox yet to make a failed sync durable/retryable (that's
    /// Phase 4), so a transient failure here just surfaces via `syncError`
    /// rather than rolling back a card the user has already swiped past.
    @discardableResult
    func applySwipe(_ swipe: ReviewResult, to wordId: UUID, now: Date = Date()) -> ReviewScheduler.Outcome? {
        guard let word = word(wordId) else { return nil }
        let outcome = ReviewScheduler.apply(swipe, to: word, now: now)
        update(outcome.word)
        Task {
            do {
                try await WordAPI.update(outcome.word)
            } catch {
                syncError = error.localizedDescription
            }
        }
        return outcome
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
            } catch {
                update(previous)
                syncError = error.localizedDescription
            }
        }
    }
}
