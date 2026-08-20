import Foundation

/// Mock data spans every status/phase combination, in both directions, so
/// the mock-first UI immediately exercises the full session-assembly logic
/// (due resurface, not-yet-due resurface, active deck at various
/// knowCounts, retired, recall not-yet-unlocked/in-progress/learnt) rather
/// than just a happy path of all-new words.
enum MockData {
    static let spanishTravel = WordCollection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Spanish — Travel",
        targetLanguage: "es",
        nativeLanguage: "en",
        createdAt: Date().addingTimeInterval(-60 * 86400)
    )

    static let germanBasics = WordCollection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "German — Basics",
        targetLanguage: "de",
        nativeLanguage: "en",
        createdAt: Date().addingTimeInterval(-30 * 86400)
    )

    static let collections: [WordCollection] = [spanishTravel, germanBasics]

    static let words: [Word] = [
        // Fresh, untouched.
        Word(
            collectionId: spanishTravel.id,
            term: "el aeropuerto",
            translation: "the airport",
            exampleSentence: "El aeropuerto está lejos del centro.",
            importance: 2,
            createdAt: Date().addingTimeInterval(-2 * 86400)
        ),
        // Mid-conveyor, one "don't know" away from being reset again.
        Word(
            collectionId: spanishTravel.id,
            term: "la maleta",
            translation: "the suitcase",
            importance: 3,
            createdAt: Date().addingTimeInterval(-5 * 86400)
        ),
        // One "know" away from graduating.
        Word(
            collectionId: spanishTravel.id,
            term: "el billete",
            translation: "the ticket",
            importance: 2,
            createdAt: Date().addingTimeInterval(-6 * 86400)
        ),
        // Recognize learnt (overdue for resurface); recall unlocked but not
        // yet started.
        Word(
            collectionId: spanishTravel.id,
            term: "el pasaporte",
            translation: "the passport",
            importance: 3,
            recallUnlockedAt: Date().addingTimeInterval(-10 * 86400),
            createdAt: Date().addingTimeInterval(-14 * 86400)
        ),
        // Recognize learnt (not due yet); recall in progress.
        Word(
            collectionId: spanishTravel.id,
            term: "la reserva",
            translation: "the reservation",
            importance: 1,
            recallUnlockedAt: Date().addingTimeInterval(-15 * 86400),
            createdAt: Date().addingTimeInterval(-20 * 86400)
        ),
        // Recognize retired; recall itself already reached learnt too.
        Word(
            collectionId: spanishTravel.id,
            term: "gracias",
            translation: "thank you",
            importance: 1,
            recallUnlockedAt: Date().addingTimeInterval(-80 * 86400),
            createdAt: Date().addingTimeInterval(-90 * 86400)
        ),
        // A second collection with just one fresh word.
        Word(
            collectionId: germanBasics.id,
            term: "der Bahnhof",
            translation: "the train station",
            importance: 2,
            createdAt: Date().addingTimeInterval(-1 * 86400)
        ),
    ]

    /// One `recognize` progress row per word (mirrors the DB's
    /// `words_seed_recognize_progress` trigger), plus a `recall` row for
    /// every word whose `recognize` track has reached `learnt`/`retired`
    /// (mirrors `word_progress_unlock_recall`).
    static let wordProgress: [WordProgress] = {
        let airport = words[0]
        let suitcase = words[1]
        let ticket = words[2]
        let passport = words[3]
        let reservation = words[4]
        let thanks = words[5]
        let trainStation = words[6]

        return [
            // Fresh, untouched.
            WordProgress(wordId: airport.id, direction: .recognize, status: .new),
            // Mid-conveyor, one "don't know" away from being reset again.
            WordProgress(wordId: suitcase.id, direction: .recognize, status: .learning, knowCount: 1, timesSeen: 2),
            // One "know" away from graduating.
            WordProgress(
                wordId: ticket.id, direction: .recognize, status: .learning,
                knowCount: SchedulingConstants.learntThreshold - 1, timesSeen: 4
            ),
            // Learnt, overdue for resurface check-in. Recall unlocked, still new.
            WordProgress(
                wordId: passport.id, direction: .recognize, status: .learnt,
                knowCount: SchedulingConstants.learntThreshold, intervalStep: 0,
                dueAt: Date().addingTimeInterval(-1 * 86400), timesSeen: 5
            ),
            WordProgress(wordId: passport.id, direction: .recall, status: .new),
            // Learnt, not due yet. Recall in progress.
            WordProgress(
                wordId: reservation.id, direction: .recognize, status: .learnt,
                knowCount: SchedulingConstants.learntThreshold, intervalStep: 1,
                dueAt: Date().addingTimeInterval(10 * 86400), timesSeen: 6
            ),
            WordProgress(wordId: reservation.id, direction: .recall, status: .learning, knowCount: 1, timesSeen: 1),
            // Recognize fully retired — proven durable, out of rotation.
            // Recall independently reached learnt and is on its own ladder.
            WordProgress(
                wordId: thanks.id, direction: .recognize, status: .retired,
                knowCount: SchedulingConstants.learntThreshold, intervalStep: 3, dueAt: nil, timesSeen: 9
            ),
            WordProgress(
                wordId: thanks.id, direction: .recall, status: .learnt,
                knowCount: SchedulingConstants.learntThreshold, intervalStep: 0,
                dueAt: Date().addingTimeInterval(5 * 86400), timesSeen: 3
            ),
            // Fresh, untouched (second collection).
            WordProgress(wordId: trainStation.id, direction: .recognize, status: .new),
        ]
    }()

    static let dailyActivity: [DailyActivity] = {
        let today = CalendarDay(date: Date())
        return (0..<5).map { offset in
            DailyActivity(activityDate: today.adding(days: -offset), reviewsCount: 12)
        }
    }()
}
