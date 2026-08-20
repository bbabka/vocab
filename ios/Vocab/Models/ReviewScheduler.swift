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

/// One word paired with its progress in the direction currently being
/// practiced — what `assembleBatch` hands back and the practice UI renders.
/// `id` is the word's, not the progress row's: a session never shows the
/// same word twice, so that's the right identity for `ForEach`/lookups here.
struct PracticeCard: Identifiable, Equatable, Sendable {
    var id: UUID { word.id }
    var word: Word
    var progress: WordProgress
}

/// The two-phase spaced-repetition engine: a conveyor "active deck" for
/// `new`/`learning` words and an expanding-interval "resurface ladder" for
/// `learnt` words. Deliberately pure and dependency-free (no Supabase, no
/// GRDB, no `Date()` called internally without an explicit `now:` parameter)
/// so every transition in the brief is a deterministic, exhaustively
/// unit-testable case — this is the single piece of logic every other layer
/// (online store, offline outbox, RPC replay) trusts to be correct.
///
/// Recall Layer (v2): this engine now operates on `WordProgress` (per-word,
/// per-direction scheduling state) rather than `Word` directly. The phase
/// math is unchanged — only the type it reads/writes moved.
enum ReviewScheduler {
    struct Outcome {
        var progress: WordProgress
        var log: ReviewLogEntry
        var activityDate: CalendarDay
    }

    /// Applies one swipe to `progress`, returning its updated state, the
    /// resulting review-log row, and the calendar day (in `calendar`'s
    /// timezone) the daily-activity bump belongs to. Does not mutate any
    /// shared state — callers own persisting the result.
    ///
    /// Precondition: `progress.status` must be `.new`, `.learning`, or
    /// `.learnt`. `assembleBatch` never returns `.retired` progress, so a
    /// `.retired` row reaching this function is a caller bug, not a runtime
    /// condition to handle gracefully.
    static func apply(
        _ swipe: ReviewResult,
        to progress: WordProgress,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Outcome {
        precondition(progress.status != .retired, "ReviewScheduler.apply called on retired progress")

        let statusBefore = progress.status
        let phase: ReviewPhase = (progress.status == .learnt) ? .resurface : .active

        var updated = progress
        switch phase {
        case .active:
            applyActiveDeckSwipe(swipe, to: &updated, now: now)
        case .resurface:
            applyResurfaceSwipe(swipe, to: &updated, now: now)
        }

        updated.timesSeen += 1
        updated.updatedAt = now

        let log = ReviewLogEntry(
            wordId: progress.wordId,
            direction: progress.direction,
            result: swipe,
            phase: phase,
            statusBefore: statusBefore,
            statusAfter: updated.status,
            reviewedAt: now
        )

        return Outcome(progress: updated, log: log, activityDate: CalendarDay(date: now, calendar: calendar))
    }

    private static func applyActiveDeckSwipe(_ swipe: ReviewResult, to progress: inout WordProgress, now: Date) {
        switch swipe {
        case .know:
            progress.knowCount += 1
            if progress.knowCount >= SchedulingConstants.learntThreshold {
                progress.status = .learnt
                progress.intervalStep = 0
                progress.dueAt = now.addingDays(SchedulingConstants.resurfaceLadderDays[0])
            }
        case .dontKnow:
            progress.knowCount = 0
            if progress.status == .new {
                progress.status = .learning
            }
        case .skip:
            break
        }
    }

    private static func applyResurfaceSwipe(_ swipe: ReviewResult, to progress: inout WordProgress, now: Date) {
        switch swipe {
        case .know:
            progress.intervalStep += 1
            if progress.intervalStep > SchedulingConstants.resurfaceLadderDays.indices.last! {
                progress.status = .retired
                progress.dueAt = nil
            } else {
                progress.dueAt = now.addingDays(SchedulingConstants.resurfaceLadderDays[progress.intervalStep])
            }
        case .dontKnow:
            progress.status = .learning
            progress.knowCount = 0
            progress.intervalStep = 0
            progress.dueAt = nil
        case .skip:
            break
        }
    }

    /// Assembles one practice batch for `direction`, exactly per the
    /// brief's session-assembly rules: due resurface words (capped at
    /// `resurfaceBatchShare` of the batch) ordered by `dueAt` ascending,
    /// backfilled from the active deck ordered by
    /// `importance desc, knowCount asc, createdAt asc`, capped at
    /// `batchSize` overall.
    ///
    /// `progress` is filtered to `direction` internally — pass every
    /// progress row you have, not a pre-filtered set. For `.recall`, a
    /// progress row existing already implies the word's `recallUnlocked`
    /// latch is open (that's the only way the row gets created), but a word
    /// with no `meanings` yet is still excluded here: an empty translation
    /// list would render a blank recall prompt, which is a content problem
    /// this filter exists to prevent, not a scheduling one.
    static func assembleBatch(
        from words: [Word],
        progress: [WordProgress],
        direction: PracticeDirection,
        batchSize: Int,
        now: Date = Date()
    ) -> [PracticeCard] {
        guard batchSize > 0 else { return [] }

        let wordsById = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        let eligible = progress.filter { entry in
            guard entry.direction == direction, let word = wordsById[entry.wordId] else { return false }
            return direction == .recognize || !word.meanings.isEmpty
        }

        func word(for entry: WordProgress) -> Word { wordsById[entry.wordId]! }

        let dueResurface = eligible
            .filter { $0.status == .learnt && ($0.dueAt ?? .distantFuture) <= now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }

        let resurfaceCap = Int(Double(batchSize) * SchedulingConstants.resurfaceBatchShare)
        let selectedResurface = Array(dueResurface.prefix(resurfaceCap))

        let activeDeck = eligible
            .filter { $0.status == .new || $0.status == .learning }
            .sorted { lhs, rhs in
                let lhsWord = word(for: lhs)
                let rhsWord = word(for: rhs)
                if lhsWord.importance != rhsWord.importance { return lhsWord.importance > rhsWord.importance }
                if lhs.knowCount != rhs.knowCount { return lhs.knowCount < rhs.knowCount }
                return lhsWord.createdAt < rhsWord.createdAt
            }

        let remaining = batchSize - selectedResurface.count
        let selectedActive = Array(activeDeck.prefix(max(0, remaining)))

        return (selectedResurface + selectedActive).map { entry in
            PracticeCard(word: word(for: entry), progress: entry)
        }
    }

    /// True when a collection currently has nothing due and nothing left on
    /// the active deck for `direction` — the brief's exact trigger for the
    /// "nothing to review" / "fully retired" state. Note this fires even if
    /// some `learnt` rows simply aren't due yet; the brief specifies this
    /// condition (nothing due + active deck empty), not a stricter check
    /// that every row has reached terminal `retired` status.
    static func isFullyRetired(_ progress: [WordProgress], direction: PracticeDirection, now: Date = Date()) -> Bool {
        let inDirection = progress.filter { $0.direction == direction }
        let hasDue = inDirection.contains { $0.status == .learnt && ($0.dueAt ?? .distantFuture) <= now }
        let hasActive = inDirection.contains { $0.status == .new || $0.status == .learning }
        return !hasDue && !hasActive
    }
}

private extension Date {
    func addingDays(_ days: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: self) ?? self
    }
}
