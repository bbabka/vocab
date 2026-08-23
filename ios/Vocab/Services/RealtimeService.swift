import Foundation
import Supabase

/// Owns a single Realtime channel subscribed to `postgres_changes` on
/// `words`, `word_progress`, `collections`, and `daily_activity` — RLS
/// scopes delivery to the signed-in user's own rows automatically, same as
/// every REST fetch. `review_log` is deliberately not subscribed
/// (write-mostly, online-only, per `ReviewStore`'s own comment). Each
/// table's incoming rows are handed to that store's own
/// `applyRealtimeChange`, which reconciles them the same way a
/// `loadFromRemote()` fetch would.
@MainActor
final class RealtimeService: ObservableObject {
    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var wordsTask: Task<Void, Never>?
    private var wordProgressTask: Task<Void, Never>?
    private var collectionsTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Idempotent — a call while already subscribed is a no-op, matching
    /// `ConnectivityMonitor.start`'s shape. Safe to call again after
    /// `stop()` (e.g. returning to the foreground), since `stop()` resets
    /// `channel` back to nil.
    func start(collectionStore: CollectionStore, wordStore: WordStore, reviewStore: ReviewStore) {
        guard channel == nil else { return }
        let channel = client.channel("db-changes")
        self.channel = channel

        let wordChanges = channel.postgresChange(AnyAction.self, table: "words")
        let wordProgressChanges = channel.postgresChange(AnyAction.self, table: "word_progress")
        let collectionChanges = channel.postgresChange(AnyAction.self, table: "collections")
        let activityChanges = channel.postgresChange(AnyAction.self, table: "daily_activity")

        wordsTask = Task { @MainActor in
            for await change in wordChanges {
                wordStore.applyRealtimeChange(change)
            }
        }
        wordProgressTask = Task { @MainActor in
            for await change in wordProgressChanges {
                wordStore.applyRealtimeProgressChange(change)
            }
        }
        collectionsTask = Task { @MainActor in
            for await change in collectionChanges {
                collectionStore.applyRealtimeChange(change)
            }
        }
        activityTask = Task { @MainActor in
            for await change in activityChanges {
                reviewStore.applyRealtimeChange(change)
            }
        }

        // `subscribeWithError()`, not the deprecated `subscribe()` — same
        // fire-and-forget shape (a failed subscribe just means Realtime
        // updates don't arrive; every store's data still lands via the
        // regular `loadFromRemote()` fetches), so the error is swallowed
        // here rather than surfaced, matching `subscribe()`'s old behavior.
        Task { try? await channel.subscribeWithError() }
    }

    /// Cancels the row-listening tasks and tears down the channel entirely
    /// (rather than just pausing consumption) so backgrounding the app
    /// doesn't leave an idle socket open, and so a later `start()` opens a
    /// fresh subscription instead of silently no-op'ing against a dead one.
    func stop() async {
        wordsTask?.cancel()
        wordProgressTask?.cancel()
        collectionsTask?.cancel()
        activityTask?.cancel()
        wordsTask = nil
        wordProgressTask = nil
        collectionsTask = nil
        activityTask = nil

        if let channel {
            await client.removeChannel(channel)
        }
        channel = nil
    }
}
