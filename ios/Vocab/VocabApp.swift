import SwiftUI

@main
struct VocabApp: App {
    @StateObject private var collectionStore = CollectionStore()
    @StateObject private var wordStore = WordStore()
    @StateObject private var reviewStore = ReviewStore()
    @StateObject private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(collectionStore)
                .environmentObject(wordStore)
                .environmentObject(reviewStore)
                .environmentObject(authStore)
        }
    }
}
