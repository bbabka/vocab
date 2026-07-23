import SwiftUI

struct WordDetailView: View {
    let wordId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var collectionStore: CollectionStore
    @State private var draft: Word?
    @State private var original: Word?

    private var collection: WordCollection? {
        guard let draft else { return nil }
        return collectionStore.collections.first { $0.id == draft.collectionId }
    }

    var body: some View {
        Group {
            if draft != nil {
                form
            } else {
                ContentUnavailableView("Word not found", systemImage: "questionmark")
            }
        }
        .navigationTitle("Word")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let word = wordStore.word(wordId)
            draft = word
            original = word
        }
        .onDisappear {
            guard let original else { return }
            wordStore.persist(wordId, previous: original)
        }
    }

    /// Only ever constructed while `draft` is known non-nil (see `body`), so
    /// the force-unwrap in `wordBinding` is safe: `draft` is set once on
    /// appear and this view never sets it back to nil.
    private var wordBinding: Binding<Word> {
        Binding(
            get: { draft! },
            set: { newValue in
                draft = newValue
                wordStore.update(newValue)
            }
        )
    }

    @ViewBuilder
    private var form: some View {
        Form {
            Section("Term") {
                TextField("Term", text: wordBinding.term)
                TextField("Pronunciation", text: optionalText(wordBinding.pronunciation))
            }

            Section("Meanings") {
                ForEach(wordBinding.meanings, editActions: .delete) { $meaning in
                    HStack {
                        Picker("Part of speech", selection: $meaning.partOfSpeech) {
                            ForEach(PartOfSpeech.allCases, id: \.self) { pos in
                                Text(pos.abbreviation.isEmpty ? "—" : pos.abbreviation).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        TextField("Meaning", text: $meaning.translation)
                    }
                }
                Button {
                    wordBinding.wrappedValue.meanings.append(WordMeaning(translation: ""))
                } label: {
                    Label("Add meaning", systemImage: "plus")
                }
            }

            Section("Example") {
                TextField("Example sentence", text: optionalText(wordBinding.exampleSentence), axis: .vertical)
                if let draft, let collection {
                    ExampleFetchButton(
                        term: draft.term,
                        languageCode: collection.targetLanguage,
                        nativeLanguageCode: collection.nativeLanguage
                    ) { example in
                        self.draft?.exampleSentence = example
                        wordStore.update(self.draft!)
                    }
                }
            }

            Section("Practice") {
                Stepper("Importance: \(wordBinding.wrappedValue.importance)", value: wordBinding.importance, in: 1...3)
                Picker("Status", selection: wordBinding.status) {
                    ForEach(WordStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
                    }
                }
            }

            Section("History") {
                LabeledContent("Times seen", value: "\(wordBinding.wrappedValue.timesSeen)")
                LabeledContent("Know count", value: "\(wordBinding.wrappedValue.knowCount)")
                if let dueAt = wordBinding.wrappedValue.dueAt {
                    LabeledContent("Next check-in", value: dueAt.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                Button {
                    guard let draft else { return }
                    SpeechService.shared.speak(draft.term, languageCode: collection?.targetLanguage ?? "en")
                } label: {
                    Label("Speak term", systemImage: "speaker.wave.2")
                }
            }
        }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview {
    NavigationStack {
        WordDetailView(wordId: MockData.words[0].id)
    }
    .environmentObject(WordStore())
    .environmentObject(CollectionStore())
}
