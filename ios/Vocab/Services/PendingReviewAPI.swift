import Foundation
import Supabase

/// Seam between `WordStore`'s outbox drain and the network, so drain
/// ordering/halt-on-failure/idempotent-double-drain behavior is testable
/// with a fake spy instead of a real Supabase project.
protocol ReviewSyncing: Sendable {
    func recordReview(_ review: PendingReview) async throws
}

struct SupabaseReviewSyncing: ReviewSyncing {
    func recordReview(_ review: PendingReview) async throws {
        try await PendingReviewAPI.recordReview(review)
    }
}

/// Calls the atomic idempotent `record_review` Postgres function — the
/// durable write path for an outbox drain. Safe to call repeatedly with the
/// same `PendingReview.id` (it doubles as `review_log.id`): the RPC no-ops
/// if that id already exists, so a retry after a crash mid-drain can't
/// double-apply a swipe.
enum PendingReviewAPI {
    private struct Params: Encodable {
        let pId: UUID
        let pWordId: UUID
        let pResult: ReviewResult
        let pPhase: ReviewPhase
        let pStatusBefore: WordStatus
        let pStatusAfter: WordStatus
        let pKnowCountAfter: Int
        let pIntervalStepAfter: Int
        let pDueAtAfter: Date?
        let pTimesSeenAfter: Int
        let pReviewedAt: Date
        let pActivityDate: CalendarDay
    }

    static func recordReview(_ review: PendingReview) async throws {
        let params = Params(
            pId: review.id,
            pWordId: review.wordId,
            pResult: review.result,
            pPhase: review.phase,
            pStatusBefore: review.statusBefore,
            pStatusAfter: review.statusAfter,
            pKnowCountAfter: review.knowCountAfter,
            pIntervalStepAfter: review.intervalStepAfter,
            pDueAtAfter: review.dueAtAfter,
            pTimesSeenAfter: review.timesSeenAfter,
            pReviewedAt: review.clientReviewedAt,
            pActivityDate: review.activityDate
        )
        try await SupabaseClientProvider.shared.rpc("record_review", params: params).execute()
    }

    /// The SQLSTATE `record_review` raises when its `words` UPDATE affects
    /// zero rows — the word doesn't exist or isn't owned by the caller (see
    /// the migration's comment on this). Distinct from a genuine idempotency
    /// no-op, which the RPC handles silently and never throws for.
    private static let wordNotFoundErrorCode = "VC001"

    /// True when `error` is that specific, permanent condition: retrying
    /// this exact review can never succeed (the word it targets is gone),
    /// so the caller should drop it from the outbox rather than treat it as
    /// a transient failure worth halting the whole drain over.
    static func isWordNotFoundError(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == wordNotFoundErrorCode
    }
}
