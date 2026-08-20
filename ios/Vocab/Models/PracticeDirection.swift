import Foundation

/// Raw values are the single source of truth shared with the DB's
/// `CHECK (direction IN ('recognize','recall'))` constraints on
/// `word_progress`/`review_log`. See `PracticeDirectionRawValueTests`.
enum PracticeDirection: String, Codable, CaseIterable, Sendable {
    /// Target → native: see `term`, recall the meaning. The original/primary
    /// skill; unlocked for every word from creation.
    case recognize
    /// Native → target: see the meaning(s), produce `term`. A distinct
    /// skill from recognition, gated behind `Word.recallUnlockedAt`.
    case recall
}
