import SwiftUI

struct AddWordView: View {
    let collectionId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var translation = ""
    @State private var exampleSentence = ""
    @State private var importance = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Term") {
                    TextField("Term", text: $term)
                    // Auto-suggested by the Translation framework in Phase 6;
                    // always editable, never blocks saving.
                    TextField("Translation", text: $translation)
                }

                Section("Example") {
                    TextField("Example sentence", text: $exampleSentence, axis: .vertical)
                }

                Section("Importance") {
                    Stepper("Importance: \(importance)", value: $importance, in: 1...3)
                }
            }
            .navigationTitle("Add Word")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        wordStore.add(
                            Word(
                                collectionId: collectionId,
                                term: term,
                                translation: translation,
                                exampleSentence: exampleSentence.isEmpty ? nil : exampleSentence,
                                importance: importance
                            )
                        )
                        dismiss()
                    }
                    .disabled(term.isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddWordView(collectionId: MockData.spanishTravel.id)
        .environmentObject(WordStore())
}
