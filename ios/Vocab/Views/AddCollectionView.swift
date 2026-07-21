import SwiftUI

struct AddCollectionView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var targetLanguage = "es"
    @State private var nativeLanguage = "en"

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Spanish — Travel", text: $name)
                }

                Section("Languages") {
                    Picker("Learning", selection: $targetLanguage) {
                        ForEach(Language.common) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    Picker("Native", selection: $nativeLanguage) {
                        ForEach(Language.common) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                }
            }
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        collectionStore.add(
                            WordCollection(name: name, targetLanguage: targetLanguage, nativeLanguage: nativeLanguage)
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddCollectionView()
        .environmentObject(CollectionStore())
}
