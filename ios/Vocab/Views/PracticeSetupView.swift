import SwiftUI

struct PracticeSetupView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @State private var selectedCollectionId: UUID?
    @State private var batchSize = 20
    @State private var isPresentingSession = false

    private let batchSizeOptions = [10, 20, 30]

    var body: some View {
        Form {
            Section("Collection") {
                Picker("Collection", selection: $selectedCollectionId) {
                    Text("All").tag(UUID?.none)
                    ForEach(collectionStore.collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
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
        .fullScreenCover(isPresented: $isPresentingSession) {
            PracticeSessionView(collectionId: selectedCollectionId, batchSize: batchSize)
        }
    }
}

#Preview {
    NavigationStack {
        PracticeSetupView()
    }
    .environmentObject(CollectionStore())
}
