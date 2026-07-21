import Foundation

/// Tunable constants for the two-phase scheduling model. Defaults match the
/// brief; safe to retune without touching `ReviewScheduler` itself.
enum SchedulingConstants {
    static let learntThreshold = 3
    /// Index `i` is the wait (in days) used when advancing to ladder step `i`.
    static let resurfaceLadderDays: [Int] = [7, 21, 60]
    /// Fraction of a practice batch reserved for due resurface words before
    /// backfilling from the active deck.
    static let resurfaceBatchShare = 1.0 / 3.0
}

/// The two-phase spaced-repetition engine: a conveyor "active deck" for
/// `new`/`learning` words and an expanding-interval "resurface ladder" for
/// `learnt` words. Deliberately pure and dependency-free (no Supabase, no
/// GRDB, no `Date()` called internally without an explicit `now:` parameter)
/// so every transition in the brief is a deterministic, exhaustively
/// unit-testable case — this is the single piece of logic every other layer
/// (online store, offline outbox, RPC replay) trusts to be correct.
enum ReviewScheduler {
    struct Outcome {
        var word: Word
        var log: ReviewLogEntry
        var activityDate: CalendarDay
    }

    /// Applies one swipe to `word`, returning its updated state, the
    /// resulting review-log row, and the calendar day (in `calendar`'s
    /// timezone) the daily-activity bump belongs to. Does not mutate any
    /// shared state — callers own persisting the result.
    ///
    /// Precondition: `word.status` must be `.new`, `.learning`, or `.learnt`.
    /// `assembleBatch` never returns `.retired` words, so a `.retired` word
    /// reaching this function is a caller bug, not a runtime condition to
    /// handle gracefully.
    static func apply(
        _ swipe: ReviewResult,
        to word: Word,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Outcome {
        precondition(word.status != .retired, "ReviewScheduler.apply called on a retired word")

        let statusBefore = word.status
        let phase: ReviewPhase = (word.status == .learnt) ? .resurface : .active

        var updated = word
        switch phase {
        case .active:
            applyActiveDeckSwipe(swipe, to: &updated, now: now)
        case .resurface:
            applyResurfaceSwipe(swipe, to: &updated, now: now)
        }

        updated.timesSeen += 1
        updated.updatedAt = now

        let log = ReviewLogEntry(
            wordId: word.id,
            result: swipe,
            phase: phase,
            statusBefore: statusBefore,
            statusAfter: updated.status,
            reviewedAt: now
        )

        return Outcome(word: updated, log: log, activityDate: CalendarDay(date: now, calendar: calendar))
    }

    private static func applyActiveDeckSwipe(_ swipe: ReviewResult, to word: inout Word, now: Date) {
        switch swipe {
        case .know:
            word.knowCount += 1
            if word.knowCount >= SchedulingConstants.learntThreshold {
                word.status = .learnt
                word.intervalStep = 0
                word.dueAt = now.addingDays(SchedulingConstants.resurfaceLadderDays[0])
            }
        case .dontKnow:
            word.knowCount = 0
            if word.status == .new {
                word.status = .learning
            }
        case .skip:
            break
        }
    }

    private static func applyResurfaceSwipe(_ swipe: ReviewResult, to word: inout Word, now: Date) {
        switch swipe {
        case .know:
            word.intervalStep += 1
            if word.intervalStep > SchedulingConstants.resurfaceLadderDays.indices.last! {
                word.status = .retired
                word.dueAt = nil
            } else {
                word.dueAt = now.addingDays(SchedulingConstants.resurfaceLadderDays[word.intervalStep])
            }
        case .dontKnow:
            word.status = .learning
            word.knowCount = 0
            word.intervalStep = 0
            word.dueAt = nil
        case .skip:
            break
        }
    }

    /// Assembles one practice batch exactly per the brief's session-assembly
    /// rules: due resurface words (capped at `resurfaceBatchShare` of the
    /// batch) ordered by `dueAt` ascending, backfilled from the active deck
    /// ordered by `importance desc, knowCount asc, createdAt asc`, capped at
    /// `batchSize` overall.
    static func assembleBatch(from words: [Word], batchSize: Int, now: Date = Date()) -> [Word] {
        guard batchSize > 0 else { return [] }

        let dueResurface = words
            .filter { $0.status == .learnt && ($0.dueAt ?? .distantFuture) <= now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }

        let resurfaceCap = Int(Double(batchSize) * SchedulingConstants.resurfaceBatchShare)
        let selectedResurface = Array(dueResurface.prefix(resurfaceCap))

        let activeDeck = words
            .filter { $0.status == .new || $0.status == .learning }
            .sorted { lhs, rhs in
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                if lhs.knowCount != rhs.knowCount { return lhs.knowCount < rhs.knowCount }
                return lhs.createdAt < rhs.createdAt
            }

        let remaining = batchSize - selectedResurface.count
        let selectedActive = Array(activeDeck.prefix(max(0, remaining)))

        return selectedResurface + selectedActive
    }

    /// True when a collection currently has nothing due and nothing left on
    /// the active deck — the brief's exact trigger for the "nothing to
    /// review" / "fully retired" state. Note this fires even if some
    /// `learnt` words simply aren't due yet; the brief specifies this
    /// condition (nothing due + active deck empty), not a stricter check
    /// that every word has reached terminal `retired` status.
    static func isFullyRetired(_ words: [Word], now: Date = Date()) -> Bool {
        let hasDue = words.contains { $0.status == .learnt && ($0.dueAt ?? .distantFuture) <= now }
        let hasActive = words.contains { $0.status == .new || $0.status == .learning }
        return !hasDue && !hasActive
    }
}

private extension Date {
    func addingDays(_ days: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: self) ?? self
    }
}
