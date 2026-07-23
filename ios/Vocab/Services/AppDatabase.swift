import Foundation
import GRDB

/// GRDB-backed local cache. Two roles, kept in one file since they share a
/// database connection and migrator:
///
/// 1. Read mirrors (`local_collections`, `local_words`, `local_daily_activity`)
///    so the app has something to show when `loadFromRemote()` can't reach
///    Supabase. `review_log` is deliberately not mirrored — it's write-mostly,
///    fine as an online-only fetch in Word Detail.
/// 2. The `pending_reviews` outbox — one row per swipe taken while offline
///    (or before the opportunistic drain catches up), replayed in order once
///    connectivity returns.
///
/// The cache is inherently single-account: it holds whichever user is
/// currently signed in on this device, not scoped by `user_id` locally, so
/// `wipe()` must run on sign-out before a different account signs in.
final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// Test/preview convenience: an in-memory database, migrated and empty.
    /// Mirrors Reader's test pattern of overriding a static container-path
    /// property to point at a temp location — GRDB's equivalent is simply
    /// constructing an in-memory `DatabaseQueue()` instead of a file-backed
    /// one.
    static func makeInMemory() -> AppDatabase {
        // swiftlint:disable:next force_try
        try! AppDatabase(dbQueue: DatabaseQueue())
    }

    static let shared: AppDatabase = {
        do {
            let folderURL = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let dbURL = folderURL.appendingPathComponent("vocab.sqlite")
            let dbQueue = try DatabaseQueue(path: dbURL.path)
            return try AppDatabase(dbQueue: dbQueue)
        } catch {
            fatalError("Failed to open local database: \(error)")
        }
    }()

    /// `nonisolated(unsafe)`: built once, never mutated after — `migrate(_:)`
    /// only reads it — so there's no actual shared mutable state despite
    /// `DatabaseMigrator` itself not being `Sendable`.
    nonisolated(unsafe) private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_local_cache_and_outbox") { db in
            try db.create(table: "local_collections") { t in
                t.column("id", .blob).primaryKey()
                t.column("name", .text).notNull()
                t.column("targetLanguage", .text).notNull()
                t.column("nativeLanguage", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "local_words") { t in
                t.column("id", .blob).primaryKey()
                t.column("collectionId", .blob).notNull().indexed()
                t.column("term", .text).notNull()
                t.column("translation", .text).notNull()
                t.column("pronunciation", .text)
                t.column("exampleSentence", .text)
                t.column("status", .text).notNull()
                t.column("importance", .integer).notNull()
                t.column("knowCount", .integer).notNull()
                t.column("intervalStep", .integer).notNull()
                t.column("dueAt", .datetime)
                t.column("timesSeen", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "local_daily_activity") { t in
                t.column("activityDate", .text).primaryKey()
                t.column("reviewsCount", .integer).notNull()
            }

            try db.create(table: "pending_reviews") { t in
                t.column("id", .blob).primaryKey()
                t.column("wordId", .blob).notNull().indexed()
                t.column("result", .text).notNull()
                t.column("phase", .text).notNull()
                t.column("statusBefore", .text).notNull()
                t.column("statusAfter", .text).notNull()
                t.column("knowCountAfter", .integer).notNull()
                t.column("intervalStepAfter", .integer).notNull()
                t.column("dueAtAfter", .datetime)
                t.column("timesSeenAfter", .integer).notNull()
                t.column("clientReviewedAt", .datetime).notNull()
                t.column("activityDate", .text).notNull()
                t.column("syncStatus", .text).notNull().defaults(to: "pending")
                t.column("attemptCount", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
            }
        }

        // `local_words` is a disposable read mirror (Postgres stays the
        // source of truth, and `loadFromRemote()` already falls back to
        // fetching remote on any local read failure) — drop-and-recreate
        // rather than an in-place `ALTER TABLE` is safe here and sidesteps
        // SQLite version differences around dropping columns.
        migrator.registerMigration("v2_word_meanings") { db in
            try db.drop(table: "local_words")
            try db.create(table: "local_words") { t in
                t.column("id", .blob).primaryKey()
                t.column("collectionId", .blob).notNull().indexed()
                t.column("term", .text).notNull()
                // Stores `[WordMeaning]` — GRDB's Codable-derived record
                // conformance JSON-encodes properties that aren't natively
                // representable database values, so no custom column
                // handling is needed beyond declaring it `.text`.
                t.column("meanings", .text).notNull()
                t.column("pronunciation", .text)
                t.column("exampleSentence", .text)
                t.column("status", .text).notNull()
                t.column("importance", .integer).notNull()
                t.column("knowCount", .integer).notNull()
                t.column("intervalStep", .integer).notNull()
                t.column("dueAt", .datetime)
                t.column("timesSeen", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        return migrator
    }()
}

// MARK: - Read mirrors

extension AppDatabase {
    func replaceCollections(_ collections: [WordCollection]) throws {
        try dbQueue.write { db in
            try WordCollection.deleteAll(db)
            for collection in collections { try collection.insert(db) }
        }
    }

    func fetchCollections() throws -> [WordCollection] {
        try dbQueue.read { db in try WordCollection.fetchAll(db) }
    }

    func upsertCollection(_ collection: WordCollection) throws {
        try dbQueue.write { db in try collection.save(db) }
    }

    func deleteCollection(_ id: UUID) throws {
        try dbQueue.write { db in _ = try WordCollection.deleteOne(db, key: id) }
    }

    /// Local-only cascade: SQLite enforces no foreign key between
    /// `local_collections` and `local_words` (they're independent mirror
    /// tables), so deleting a collection must explicitly purge its words
    /// too — otherwise they'd survive in the offline-read fallback as
    /// orphans referencing a collection that's gone everywhere else.
    func deleteWords(forCollectionId collectionId: UUID) throws {
        try dbQueue.write { db in
            try Word.filter(Column("collectionId") == collectionId).deleteAll(db)
        }
    }

    func replaceWords(_ words: [Word]) throws {
        try dbQueue.write { db in
            try Word.deleteAll(db)
            for word in words { try word.insert(db) }
        }
    }

    func fetchWords() throws -> [Word] {
        try dbQueue.read { db in try Word.fetchAll(db) }
    }

    func upsertWord(_ word: Word) throws {
        try dbQueue.write { db in try word.save(db) }
    }

    func deleteWord(_ id: UUID) throws {
        try dbQueue.write { db in _ = try Word.deleteOne(db, key: id) }
    }

    func replaceDailyActivity(_ activity: [DailyActivity]) throws {
        try dbQueue.write { db in
            try DailyActivity.deleteAll(db)
            for row in activity { try row.insert(db) }
        }
    }

    func fetchDailyActivity() throws -> [DailyActivity] {
        try dbQueue.read { db in try DailyActivity.fetchAll(db) }
    }

    func upsertDailyActivity(_ activity: DailyActivity) throws {
        try dbQueue.write { db in try activity.save(db) }
    }
}

// MARK: - Outbox

extension AppDatabase {
    func enqueuePendingReview(_ review: PendingReview) throws {
        try dbQueue.write { db in try review.insert(db) }
    }

    /// Strict `clientReviewedAt` ascending order — the same word can recur
    /// across multiple queued offline swipes, so replay order matters beyond
    /// what the idempotent insert alone protects.
    func fetchPendingReviews() throws -> [PendingReview] {
        try dbQueue.read { db in
            try PendingReview.order(sql: "clientReviewedAt ASC").fetchAll(db)
        }
    }

    func deletePendingReview(_ id: UUID) throws {
        try dbQueue.write { db in _ = try PendingReview.deleteOne(db, key: id) }
    }

    /// Drops any still-queued reviews for a word that's being deleted — once
    /// the word is gone, those rows can never apply (the RPC has nothing to
    /// update), so leaving them queued would just make `drainOutbox()` hit
    /// the "word not found" error on every future attempt.
    func deletePendingReviews(forWordId wordId: UUID) throws {
        try dbQueue.write { db in
            try PendingReview.filter(Column("wordId") == wordId).deleteAll(db)
        }
    }

    func markPendingReviewFailed(_ id: UUID, error: String) throws {
        try dbQueue.write { db in
            guard var review = try PendingReview.fetchOne(db, key: id) else { return }
            review.attemptCount += 1
            review.syncStatus = .failed
            review.lastError = error
            try review.update(db)
        }
    }
}

// MARK: - Sign-out hygiene

extension AppDatabase {
    /// Clears every local table. Must run on sign-out: the cache isn't
    /// scoped by `user_id`, so leaving it in place risks a second account
    /// signing in on the same device and reading the first account's data.
    func wipe() throws {
        try dbQueue.write { db in
            try WordCollection.deleteAll(db)
            try Word.deleteAll(db)
            try DailyActivity.deleteAll(db)
            try PendingReview.deleteAll(db)
        }
    }
}

// MARK: - GRDB record conformances

extension WordStatus: DatabaseValueConvertible {}
extension ReviewResult: DatabaseValueConvertible {}
extension ReviewPhase: DatabaseValueConvertible {}
extension SyncStatus: DatabaseValueConvertible {}

/// Stored as `CalendarDay.isoString` — the same plain `"yyyy-MM-dd"` text its
/// `Codable` conformance already produces for Postgres — one format, two
/// backends, parsed/rendered in exactly one place (`CalendarDay.swift`).
extension CalendarDay: DatabaseValueConvertible {
    var databaseValue: DatabaseValue {
        isoString.databaseValue
    }

    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> CalendarDay? {
        guard let string = String.fromDatabaseValue(dbValue) else { return nil }
        return CalendarDay(isoString: string)
    }
}

extension WordCollection: FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_collections"
}

extension Word: FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_words"
}

extension DailyActivity: FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_daily_activity"
}

extension PendingReview: FetchableRecord, PersistableRecord {
    static let databaseTableName = "pending_reviews"
}
