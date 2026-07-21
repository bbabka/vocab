import SwiftUI

struct RootView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var connectivityMonitor = ConnectivityMonitor()

    var body: some View {
        Group {
            if authStore.session != nil {
                mainTabs
            } else {
                AuthView()
            }
        }
        .task {
            await authStore.observeAuthState()
        }
        .onChange(of: authStore.session == nil) { _, isSignedOut in
            // The stores are long-lived `@StateObject`s that outlive any
            // single session — without this, a newly signed-in different
            // account would briefly see (or fall back to) the previous
            // account's in-memory data. `AppDatabase.wipe()` already clears
            // the GRDB layer inside `AuthStore.signOut()`; this clears the
            // matching in-memory state the stores hold on top of it.
            if isSignedOut {
                collectionStore.reset()
                wordStore.reset()
                reviewStore.reset()
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                CollectionsListView()
            }
            .tabItem { Label("Collections", systemImage: "square.stack") }

            NavigationStack {
                PracticeSetupView()
            }
            .tabItem { Label("Practice", systemImage: "rectangle.on.rectangle") }

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("Stats", systemImage: "chart.bar") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            // No-op in Phase 1 (mock data); becomes real once Phase 3 wires
            // Supabase-backed stores. Kept here now so this wiring never
            // needs to change shape later, matching Reader's RootView.
            async let collections: () = collectionStore.loadFromRemote()
            async let wordsLoad: () = wordStore.loadFromRemote()
            async let reviews: () = reviewStore.loadFromRemote()
            _ = await (collections, wordsLoad, reviews)

            // Outbox drain trigger #1 (launch); trigger #2 is reconnect,
            // wired below via `connectivityMonitor.start`.
            await drainAndRefreshActivity()
        }
        .task {
            connectivityMonitor.start {
                Task { await drainAndRefreshActivity() }
            }
        }
    }

    /// Drains the outbox, then re-fetches `dailyActivity` so a swipe that
    /// syncs during this drain is reflected locally right away. Without
    /// this, `reviewStore.loadFromRemote()` (already run once, before the
    /// drain, in the launch `.task` above) would keep showing a stale local
    /// count until some *subsequent* launch's fetch finally lands after an
    /// already-completed drain.
    private func drainAndRefreshActivity() async {
        await wordStore.drainOutbox()
        await reviewStore.loadFromRemote()
    }
}

#Preview {
    RootView()
        .environmentObject(CollectionStore())
        .environmentObject(WordStore())
        .environmentObject(ReviewStore())
        .environmentObject(AuthStore())
}
