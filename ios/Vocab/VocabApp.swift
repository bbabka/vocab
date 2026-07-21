import SwiftUI

@main
struct VocabApp: App {
    @StateObject private var collectionStore = CollectionStore()
    @StateObject private var wordStore = WordStore()
    @StateObject private var reviewStore = ReviewStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(collectionStore)
                .environmentObject(wordStore)
                .environmentObject(reviewStore)
        }
    }
}
