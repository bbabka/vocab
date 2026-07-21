import Foundation

@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var words: [Word]

    init(words: [Word] = MockData.words) {
        self.words = words
    }

    /// No-op until Phase 3 wires a real Supabase-backed implementation.
    func loadFromRemote() async {}

    func words(in collectionId: UUID) -> [Word] {
        words.filter { $0.collectionId == collectionId }
    }

    func word(_ id: UUID) -> Word? {
        words.first { $0.id == id }
    }

    func add(_ word: Word) {
        words.append(word)
    }

    func update(_ word: Word) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
    }

    func delete(_ wordId: UUID) {
        words.removeAll { $0.id == wordId }
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
    @discardableResult
    func applySwipe(_ swipe: ReviewResult, to wordId: UUID, now: Date = Date()) -> ReviewScheduler.Outcome? {
        guard let word = word(wordId) else { return nil }
        let outcome = ReviewScheduler.apply(swipe, to: word, now: now)
        update(outcome.word)
        return outcome
    }

    /// Manual override from Word Detail: force a status, resetting the
    /// scheduling fields to sensible defaults for that status per the brief.
    func setStatus(_ status: WordStatus, for wordId: UUID, now: Date = Date()) {
        guard var word = word(wordId) else { return }
        word.status = status
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
        word.updatedAt = now
        update(word)
    }
}
