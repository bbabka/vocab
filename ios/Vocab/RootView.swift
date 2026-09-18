import SwiftUI

struct RootView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var connectivityMonitor = ConnectivityMonitor()
    @StateObject private var realtimeService = RealtimeService()
    @Environment(\.scenePhase) private var scenePhase

    /// True once the post-sign-in initial load (`loadInitialData()`) has
    /// completed. Every store starts seeded with `MockData` (see each
    /// store's `init`) so previews/tests have something to render — without
    /// this gate, `mainTabs` would mount immediately on sign-in and every
    /// tab would flash that placeholder data for the moment it takes the
    /// real fetch to land.
    @State private var hasLoadedInitialData = false

    var body: some View {
        Group {
            if authStore.isInitializing || (authStore.session != nil && !hasLoadedInitialData) {
                SplashView()
            } else if authStore.session != nil {
                mainTabs
            } else {
                AuthView()
            }
        }
        .task {
            await authStore.observeAuthState()
        }
        // Keyed on the signed-in user's id, not just "is there a session":
        // restarts this load if a different account signs in, and — unlike
        // attaching it to `mainTabs` itself — runs independently of whether
        // `mainTabs` is currently mounted, so it can be the thing that
        // decides when `mainTabs` is allowed to mount in the first place.
        .task(id: authStore.session?.user.id) {
            guard authStore.session != nil else { return }
            await loadInitialData()
            // Initial subscribe on first appearance after sign-in; the
            // scenePhase handler below takes over for subsequent
            // background/foreground transitions during this same session.
            realtimeService.start(collectionStore: collectionStore, wordStore: wordStore, reviewStore: reviewStore)
            hasLoadedInitialData = true
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
                // Device-wide UserDefaults, not scoped by account — without
                // this, a second account signing in on this device would
                // inherit the first account's Practice collection selection.
                UserDefaults.standard.removeObject(forKey: PracticeSetupView.selectedCollectionIdsKey)
                hasLoadedInitialData = false
                Task { await realtimeService.stop() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Tears the subscription down in the background rather than
            // just pausing consumption, so a backgrounded app doesn't hold
            // an idle socket open; `.inactive` (transient, e.g. control
            // center or the app switcher) is deliberately ignored to avoid
            // churning the channel on every brief foreground flicker.
            guard authStore.session != nil else { return }
            switch newPhase {
            case .active:
                realtimeService.start(collectionStore: collectionStore, wordStore: wordStore, reviewStore: reviewStore)
            case .background:
                Task { await realtimeService.stop() }
            default:
                break
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
        }
        .task {
            connectivityMonitor.start {
                Task { await drainAndRefreshActivity() }
            }
        }
    }

    private func loadInitialData() async {
        async let collections: () = collectionStore.loadFromRemote()
        async let wordsLoad: () = wordStore.loadFromRemote()
        async let reviews: () = reviewStore.loadFromRemote()
        _ = await (collections, wordsLoad, reviews)

        // Outbox drain trigger #1 (launch); trigger #2 is reconnect, wired
        // in `mainTabs` via `connectivityMonitor.start`.
        await drainAndRefreshActivity()
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
