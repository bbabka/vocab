import SwiftUI

struct CollectionsListView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var wordStore: WordStore
    @State private var isPresentingNewCollection = false
    @State private var isPresentingSettings = false
    @State private var renamingCollection: WordCollection?
    @State private var renameText = ""

    var body: some View {
        // Computed once per render, not once per row — `recognizeStatusByWordId`
        // rebuilds its dictionary from `wordStore.wordProgress` on every access.
        let recognizeStatusByWordId = wordStore.recognizeStatusByWordId
        List {
            ForEach(collectionStore.collections) { collection in
                NavigationLink(value: CollectionRoute(id: collection.id)) {
                    CollectionRow(collection: collection, words: wordStore.words(in: collection.id), recognizeStatusByWordId: recognizeStatusByWordId)
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isPresentingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
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
        .sheet(isPresented: $isPresentingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPresentingSettings = false }
                        }
                    }
            }
        }
        .alert("Rename Collection", isPresented: Binding(
            get: { renamingCollection != nil },
            set: { isPresented in if !isPresented { renamingCollection = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingCollection = nil }
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renamingCollection, !trimmed.isEmpty {
                    collectionStore.rename(renamingCollection.id, to: trimmed)
                }
                renamingCollection = nil
            }
        }
    }
}

private struct CollectionRow: View {
    let collection: WordCollection
    let words: [Word]
    let recognizeStatusByWordId: [UUID: WordStatus]

    private var learntCount: Int {
        words.filter { recognizeStatusByWordId[$0.id] == .learnt || recognizeStatusByWordId[$0.id] == .retired }.count
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
