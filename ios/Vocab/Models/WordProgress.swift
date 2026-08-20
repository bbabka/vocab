import Foundation

/// Scheduling state for one word in one direction — what used to live
/// directly on `Word` before the Recall Layer (v2) split it off so
/// `recognize` and `recall` can be scheduled independently. See
/// vocab-rev_direction-brief.md's "Recall Layer" section.
///
/// The client never inserts or deletes these rows directly: creation is
/// entirely server-side (a trigger seeds the `recognize` row on word
/// insert, another creates the `recall` row when `recognize` first reaches
/// `learnt`), and updates only ever flow through the `record_review` RPC or
/// a manual status override. That's a deliberate structural choice, not an
/// oversight — see `WordStore.setStatus`.
struct WordProgress: Codable, Equatable, Sendable {
    var id: UUID
    var wordId: UUID
    var direction: PracticeDirection
    var status: WordStatus
    var knowCount: Int
    var intervalStep: Int
    var dueAt: Date?
    var timesSeen: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        wordId: UUID,
        direction: PracticeDirection,
        status: WordStatus = .new,
        knowCount: Int = 0,
        intervalStep: Int = 0,
        dueAt: Date? = nil,
        timesSeen: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.wordId = wordId
        self.direction = direction
        self.status = status
        self.knowCount = knowCount
        self.intervalStep = intervalStep
        self.dueAt = dueAt
        self.timesSeen = timesSeen
        self.updatedAt = updatedAt
    }

    /// The stable client-predictable identity: `id` is server-generated and
    /// unknown to the client until the row is first fetched (the client
    /// never inserts one itself), so every lookup/merge/reconciliation uses
    /// this composite key instead — matching the DB's own
    /// `unique (word_id, direction)` constraint.
    var key: WordProgressKey { WordProgressKey(wordId: wordId, direction: direction) }
}

struct WordProgressKey: Hashable, Sendable {
    var wordId: UUID
    var direction: PracticeDirection
}
