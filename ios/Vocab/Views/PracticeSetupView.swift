import SwiftUI

struct PracticeSetupView: View {
    /// Shared with `RootView`'s sign-out handler, which must clear this key
    /// — otherwise a second account signing in on the same device would
    /// inherit the first account's collection selection, silently filtering
    /// its practice pool down to collection ids that don't belong to it.
    static let selectedCollectionIdsKey = "practiceSelectedCollectionIds"

    @EnvironmentObject private var collectionStore: CollectionStore
    @AppStorage(Self.selectedCollectionIdsKey) private var selectedCollectionIdsStorage = ""
    @State private var batchSize = 20
    @State private var direction: PracticeDirection = .recognize
    @State private var isPresentingSession = false

    private let batchSizeOptions = [10, 20, 30]

    private var selectedCollectionIds: Set<UUID> {
        get {
            Set(selectedCollectionIdsStorage.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        }
        nonmutating set {
            selectedCollectionIdsStorage = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Direction", selection: $direction) {
                    Text("Recognize").tag(PracticeDirection.recognize)
                    Text("Recall").tag(PracticeDirection.recall)
                }
                .pickerStyle(.segmented)

                Button("Start Practice") {
                    isPresentingSession = true
                }
            } header: {
                Text("Direction")
            } footer: {
                switch direction {
                case .recognize:
                    Text("See the word, recall its meaning.")
                case .recall:
                    Text("See the meaning, produce the word. Only words you've already learnt to recognize are eligible — recall has its own progress and schedule.")
                }
            }

            Section {
                Button {
                    selectedCollectionIds = []
                } label: {
                    HStack {
                        Text("All")
                        Spacer()
                        if selectedCollectionIds.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)

                ForEach(collectionStore.collections) { collection in
                    Button {
                        if selectedCollectionIds.contains(collection.id) {
                            selectedCollectionIds.remove(collection.id)
                        } else {
                            selectedCollectionIds.insert(collection.id)
                        }
                    } label: {
                        HStack {
                            Text(collection.name)
                            Spacer()
                            if selectedCollectionIds.contains(collection.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Collections")
            } footer: {
                Text("Select one or more collections, or leave on \"All\".")
            }

            Section("Batch size") {
                Picker("Batch size", selection: $batchSize) {
                    ForEach(batchSizeOptions, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Practice")
        .refreshable {
            await collectionStore.loadFromRemote()
        }
        .fullScreenCover(isPresented: $isPresentingSession) {
            PracticeSessionView(collectionIds: selectedCollectionIds, batchSize: batchSize, direction: direction)
        }
    }
}

#Preview {
    NavigationStack {
        PracticeSetupView()
    }
    .environmentObject(CollectionStore())
}
