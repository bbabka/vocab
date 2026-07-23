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

/// Raw values are the single source of truth shared with the DB's
/// `CHECK` constraint validating every `meanings[].part_of_speech` — see
/// `PartOfSpeechRawValueTests`, the canary test guarding against drift
/// between this enum and that constraint (mirrors `WordStatus`'s own).
enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun
    case verb
    case adjective
    case adverb
    case pronoun
    case preposition
    case conjunction
    case interjection
    case other

    var abbreviation: String {
        switch self {
        case .noun: "n."
        case .verb: "v."
        case .adjective: "adj."
        case .adverb: "adv."
        case .pronoun: "pron."
        case .preposition: "prep."
        case .conjunction: "conj."
        case .interjection: "interj."
        case .other: ""
        }
    }
}

/// A term frequently has more than one sense (e.g. Spanish "banco" = "bank"
/// (noun) or "bench" (noun); "llamar" = "to call") — `Word` holds a list of
/// these rather than a single `translation` string so each sense can carry
/// its own part-of-speech marker.
struct WordMeaning: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var translation: String
    var partOfSpeech: PartOfSpeech

    init(id: UUID = UUID(), translation: String, partOfSpeech: PartOfSpeech = .other) {
        self.id = id
        self.translation = translation
        self.partOfSpeech = partOfSpeech
    }
}

struct Word: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var collectionId: UUID
    var term: String
    var meanings: [WordMeaning]
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
        meanings: [WordMeaning] = [],
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
        self.meanings = meanings
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

    /// Convenience for the many call sites (mocks, tests, quick manual
    /// entry) that only need a single plain-text meaning.
    init(
        id: UUID = UUID(),
        collectionId: UUID,
        term: String,
        translation: String,
        partOfSpeech: PartOfSpeech = .other,
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
        self.init(
            id: id,
            collectionId: collectionId,
            term: term,
            meanings: translation.isEmpty ? [] : [WordMeaning(translation: translation, partOfSpeech: partOfSpeech)],
            pronunciation: pronunciation,
            exampleSentence: exampleSentence,
            status: status,
            importance: importance,
            knowCount: knowCount,
            intervalStep: intervalStep,
            dueAt: dueAt,
            timesSeen: timesSeen,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
