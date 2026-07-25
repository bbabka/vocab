import SwiftUI

struct PracticeSetupView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @State private var selectedCollectionIds: Set<UUID> = []
    @State private var batchSize = 20
    @State private var isPresentingSession = false

    private let batchSizeOptions = [10, 20, 30]

    var body: some View {
        Form {
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

            Section {
                Button("Start Practice") {
                    isPresentingSession = true
                }
            }
        }
        .navigationTitle("Practice")
        .refreshable {
            await collectionStore.loadFromRemote()
        }
        .fullScreenCover(isPresented: $isPresentingSession) {
            PracticeSessionView(collectionIds: selectedCollectionIds, batchSize: batchSize)
        }
    }
}

#Preview {
    NavigationStack {
        PracticeSetupView()
    }
    .environmentObject(CollectionStore())
}
