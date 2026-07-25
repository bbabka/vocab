import SwiftUI

struct CollectionsListView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var wordStore: WordStore
    @State private var isPresentingNewCollection = false
    @State private var renamingCollection: WordCollection?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(collectionStore.collections) { collection in
                NavigationLink(value: CollectionRoute(id: collection.id)) {
                    CollectionRow(collection: collection, words: wordStore.words(in: collection.id))
                }
                .swipeActions(edge: .leading) {
                    Button {
                        renamingCollection = collection
                        renameText = collection.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        renamingCollection = collection
                        renameText = collection.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    collectionStore.delete(collectionStore.collections[index].id)
                }
            }
        }
        .navigationTitle("Collections")
        .refreshable {
            async let collections: () = collectionStore.loadFromRemote()
            async let words: () = wordStore.loadFromRemote()
            _ = await (collections, words)
        }
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
        .alert("Rename Collection", isPresented: Binding(
            get: { renamingCollection != nil },
            set: { isPresented in if !isPresented { renamingCollection = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingCollection = nil }
            Button("Save") {
                if let renamingCollection, !renameText.isEmpty {
                    collectionStore.rename(renamingCollection.id, to: renameText)
                }
                renamingCollection = nil
            }
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
