import SwiftUI

struct CollectionsListView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var wordStore: WordStore
    @State private var isPresentingNewCollection = false

    var body: some View {
        List {
            ForEach(collectionStore.collections) { collection in
                NavigationLink(value: CollectionRoute(id: collection.id)) {
                    CollectionRow(collection: collection, words: wordStore.words(in: collection.id))
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    collectionStore.delete(collectionStore.collections[index].id)
                }
            }
        }
        .navigationTitle("Collections")
        .navigationDestination(for: CollectionRoute.self) { route in
            WordListView(collectionId: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNewCollection = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewCollection) {
            AddCollectionView()
        }
    }
}

private struct CollectionRow: View {
    let collection: WordCollection
    let words: [Word]

    private var learntCount: Int {
        words.filter { $0.status == .learnt || $0.status == .retired }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.name)
                .font(.headline)
            Text("\(collection.targetLanguage.uppercased()) → \(collection.nativeLanguage.uppercased()) · \(learntCount)/\(words.count) learnt")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        CollectionsListView()
    }
    .environmentObject(CollectionStore())
    .environmentObject(WordStore())
}
