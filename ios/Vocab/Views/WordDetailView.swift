import SwiftUI

struct WordDetailView: View {
    let wordId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var collectionStore: CollectionStore
    @State private var draft: Word?
    @State private var original: Word?
    @State private var isEditing = false

    private var collection: WordCollection? {
        guard let draft else { return nil }
        return collectionStore.collections.first { $0.id == draft.collectionId }
    }

    var body: some View {
        Group {
            if let draft {
                if isEditing {
                    editForm
                } else {
                    detail(for: draft)
                }
            } else {
                ContentUnavailableView("Word not found", systemImage: "questionmark")
            }
        }
        .navigationTitle("Word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if draft != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Done" : "Edit") {
                        isEditing.toggle()
                    }
                }
            }
        }
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

    // MARK: - Detail

    @ViewBuilder
    private func detail(for word: Word) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                wordCard(word)
                statsCard(word)
            }
            .padding()
        }
    }

    private func wordCard(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.term)
                        .font(.largeTitle.bold())
                    if let pronunciation = word.pronunciation, !pronunciation.isEmpty {
                        Text(pronunciation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(status: word.status)
            }

            if !word.meanings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(word.meanings) { meaning in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if !meaning.partOfSpeech.abbreviation.isEmpty {
                                Text(meaning.partOfSpeech.abbreviation)
                                    .font(.subheadline)
                                    .italic()
                                    .foregroundStyle(.secondary)
                            }
                            Text(meaning.translation)
                                .font(.title3)
                        }
                    }
                }
            }

            if let example = word.exampleSentence, !example.isEmpty {
                Divider()
                Text(example)
                    .font(.body)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            Button {
                SpeechService.shared.speak(word.term, languageCode: collection?.targetLanguage ?? "en")
            } label: {
                Label("Speak", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statsCard(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stats")
                .font(.headline)
                .padding(.bottom, 8)

            statRow("Status", value: word.status.rawValue.capitalized)
            Divider()
            statRow("Importance", value: String(repeating: "★", count: word.importance))
            Divider()
            statRow("Times seen", value: "\(word.timesSeen)")
            Divider()
            statRow("Know count", value: "\(word.knowCount)")
            if let dueAt = word.dueAt {
                Divider()
                statRow("Next check-in", value: dueAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Editing

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
    private var editForm: some View {
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
