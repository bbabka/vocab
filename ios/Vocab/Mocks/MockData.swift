import Foundation

/// Mock data spans every status/phase combination so the mock-first UI
/// immediately exercises the full session-assembly logic (due resurface,
/// not-yet-due resurface, active deck at various knowCounts, retired) rather
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
            status: .new,
            importance: 2,
            createdAt: Date().addingTimeInterval(-2 * 86400)
        ),
        // Mid-conveyor, one "don't know" away from being reset again.
        Word(
            collectionId: spanishTravel.id,
            term: "la maleta",
            translation: "the suitcase",
            status: .learning,
            importance: 3,
            knowCount: 1,
            timesSeen: 2,
            createdAt: Date().addingTimeInterval(-5 * 86400)
        ),
        // One "know" away from graduating.
        Word(
            collectionId: spanishTravel.id,
            term: "el billete",
            translation: "the ticket",
            status: .learning,
            importance: 2,
            knowCount: SchedulingConstants.learntThreshold - 1,
            timesSeen: 4,
            createdAt: Date().addingTimeInterval(-6 * 86400)
        ),
        // Learnt, overdue for resurface check-in.
        Word(
            collectionId: spanishTravel.id,
            term: "el pasaporte",
            translation: "the passport",
            status: .learnt,
            importance: 3,
            knowCount: SchedulingConstants.learntThreshold,
            intervalStep: 0,
            dueAt: Date().addingTimeInterval(-1 * 86400),
            timesSeen: 5,
            createdAt: Date().addingTimeInterval(-14 * 86400)
        ),
        // Learnt, not due yet.
        Word(
            collectionId: spanishTravel.id,
            term: "la reserva",
            translation: "the reservation",
            status: .learnt,
            importance: 1,
            knowCount: SchedulingConstants.learntThreshold,
            intervalStep: 1,
            dueAt: Date().addingTimeInterval(10 * 86400),
            timesSeen: 6,
            createdAt: Date().addingTimeInterval(-20 * 86400)
        ),
        // Fully retired — proven durable, out of rotation.
        Word(
            collectionId: spanishTravel.id,
            term: "gracias",
            translation: "thank you",
            status: .retired,
            importance: 1,
            knowCount: SchedulingConstants.learntThreshold,
            intervalStep: 3,
            dueAt: nil,
            timesSeen: 9,
            createdAt: Date().addingTimeInterval(-90 * 86400)
        ),
        // A second collection with just one fresh word.
        Word(
            collectionId: germanBasics.id,
            term: "der Bahnhof",
            translation: "the train station",
            status: .new,
            importance: 2,
            createdAt: Date().addingTimeInterval(-1 * 86400)
        ),
    ]

    static let dailyActivity: [DailyActivity] = {
        let today = CalendarDay(date: Date())
        return (0..<5).map { offset in
            DailyActivity(activityDate: today.adding(days: -offset), reviewsCount: 12)
        }
    }()
}
