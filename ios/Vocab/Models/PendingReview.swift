import Foundation

/// Where a queued swipe stands in the outbox lifecycle. `pending` covers both
/// "never attempted yet" and "attempted, waiting to retry" — `attemptCount`/
/// `lastError` carry the retry detail; `failed` just flags that at least one
/// attempt has errored, for surfacing in UI if needed later.
enum SyncStatus: String, Codable, Sendable {
    case pending
    case failed
}

/// One row per swipe — the outbox's atomic unit of replay. Carries the
/// `ReviewScheduler`'s already-computed after-state (rather than re-deriving
/// the transition server-side) plus everything the `record_review` RPC needs
/// to reproduce the three writes (`words` update, `review_log` insert,
/// `daily_activity` upsert) atomically and idempotently on the far side.
///
/// `id` doubles as the idempotency key: it's the client-generated UUID that
/// becomes `review_log.id`, so replaying the same row twice (e.g. a retry
/// after a crash mid-drain) is safe — the RPC no-ops if that id already
/// exists.
struct PendingReview: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var wordId: UUID
    var result: ReviewResult
    var phase: ReviewPhase
    var statusBefore: WordStatus
    var statusAfter: WordStatus
    var knowCountAfter: Int
    var intervalStepAfter: Int
    var dueAtAfter: Date?
    var timesSeenAfter: Int
    var clientReviewedAt: Date
    var activityDate: CalendarDay
    var syncStatus: SyncStatus
    var attemptCount: Int
    var lastError: String?

    /// `id` is `outcome.log.id`, not a freshly generated one — the outbox row
    /// and the `review_log` row it will produce must share an id for the
    /// RPC's idempotency check to mean anything.
    init(outcome: ReviewScheduler.Outcome) {
        self.id = outcome.log.id
        self.wordId = outcome.log.wordId
        self.result = outcome.log.result
        self.phase = outcome.log.phase
        self.statusBefore = outcome.log.statusBefore
        self.statusAfter = outcome.log.statusAfter
        self.knowCountAfter = outcome.word.knowCount
        self.intervalStepAfter = outcome.word.intervalStep
        self.dueAtAfter = outcome.word.dueAt
        self.timesSeenAfter = outcome.word.timesSeen
        self.clientReviewedAt = outcome.log.reviewedAt
        self.activityDate = outcome.activityDate
        self.syncStatus = .pending
        self.attemptCount = 0
        self.lastError = nil
    }
}
