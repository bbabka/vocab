import Foundation

struct ReviewLogEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var wordId: UUID
    var direction: PracticeDirection
    var result: ReviewResult
    var phase: ReviewPhase
    var statusBefore: WordStatus
    var statusAfter: WordStatus
    var reviewedAt: Date

    init(
        id: UUID = UUID(),
        wordId: UUID,
        direction: PracticeDirection,
        result: ReviewResult,
        phase: ReviewPhase,
        statusBefore: WordStatus,
        statusAfter: WordStatus,
        reviewedAt: Date = Date()
    ) {
        self.id = id
        self.wordId = wordId
        self.direction = direction
        self.result = result
        self.phase = phase
        self.statusBefore = statusBefore
        self.statusAfter = statusAfter
        self.reviewedAt = reviewedAt
    }
}
