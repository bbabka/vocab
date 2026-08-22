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
        let pDirection: PracticeDirection
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

        /// `pDueAtAfter` is `nil` for every word still `new`/`learning` —
        /// the common case, since `dueAt` is only set once a word reaches
        /// `learnt`. Synthesized `Encodable` would omit a `nil` Optional's
        /// key entirely rather than write `null`, but `record_review`'s
        /// `p_due_at_after` parameter has no SQL default, so PostgREST can't
        /// resolve the function when the key is missing — every such call
        /// fails with a schema-cache error, not the `VC001` this module
        /// specifically watches for, which silently jams the whole outbox
        /// (see `WordStore.drainOutbox`). Encoding explicitly keeps the key
        /// present (as `null`) so the call always matches.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(pId, forKey: .pId)
            try container.encode(pWordId, forKey: .pWordId)
            try container.encode(pDirection, forKey: .pDirection)
            try container.encode(pResult, forKey: .pResult)
            try container.encode(pPhase, forKey: .pPhase)
            try container.encode(pStatusBefore, forKey: .pStatusBefore)
            try container.encode(pStatusAfter, forKey: .pStatusAfter)
            try container.encode(pKnowCountAfter, forKey: .pKnowCountAfter)
            try container.encode(pIntervalStepAfter, forKey: .pIntervalStepAfter)
            try container.encode(pDueAtAfter, forKey: .pDueAtAfter)
            try container.encode(pTimesSeenAfter, forKey: .pTimesSeenAfter)
            try container.encode(pReviewedAt, forKey: .pReviewedAt)
            try container.encode(pActivityDate, forKey: .pActivityDate)
        }

        private enum CodingKeys: String, CodingKey {
            case pId, pWordId, pDirection, pResult, pPhase, pStatusBefore, pStatusAfter
            case pKnowCountAfter, pIntervalStepAfter, pDueAtAfter, pTimesSeenAfter
            case pReviewedAt, pActivityDate
        }
    }

    static func recordReview(_ review: PendingReview) async throws {
        let params = Params(
            pId: review.id,
            pWordId: review.wordId,
            pDirection: review.direction,
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
