import SwiftUI

struct RootView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore

    var body: some View {
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
        }
    }
}

#Preview {
    RootView()
        .environmentObject(CollectionStore())
        .environmentObject(WordStore())
        .environmentObject(ReviewStore())
}
