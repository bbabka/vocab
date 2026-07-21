import Foundation

/// Raw values are the single source of truth shared with the DB's
/// `CHECK (status IN ('new','learning','learnt','retired'))` constraint.
/// See `WordStatusRawValueTests` — it exists specifically to catch drift
/// between this enum and that constraint.
enum WordStatus: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case learnt
    case retired
}

enum ReviewResult: String, Codable, Sendable {
    case know
    case dontKnow = "dont_know"
    case skip
}

enum ReviewPhase: String, Codable, Sendable {
    case active
    case resurface
}

struct Word: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var collectionId: UUID
    var term: String
    var translation: String
    var pronunciation: String?
    var exampleSentence: String?
    var status: WordStatus
    var importance: Int
    var knowCount: Int
    var intervalStep: Int
    var dueAt: Date?
    var timesSeen: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        collectionId: UUID,
        term: String,
        translation: String,
        pronunciation: String? = nil,
        exampleSentence: String? = nil,
        status: WordStatus = .new,
        importance: Int = 2,
        knowCount: Int = 0,
        intervalStep: Int = 0,
        dueAt: Date? = nil,
        timesSeen: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collectionId = collectionId
        self.term = term
        self.translation = translation
        self.pronunciation = pronunciation
        self.exampleSentence = exampleSentence
        self.status = status
        self.importance = importance
        self.knowCount = knowCount
        self.intervalStep = intervalStep
        self.dueAt = dueAt
        self.timesSeen = timesSeen
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
