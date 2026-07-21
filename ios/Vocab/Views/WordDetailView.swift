import SwiftUI

struct WordDetailView: View {
    let wordId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @State private var draft: Word?
    @State private var original: Word?

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
                TextField("Translation", text: wordBinding.translation)
                TextField("Pronunciation", text: optionalText(wordBinding.pronunciation))
            }

            Section("Example") {
                TextField("Example sentence", text: optionalText(wordBinding.exampleSentence), axis: .vertical)
                Button {
                    // Tatoeba fetch wired in Phase 6.
                } label: {
                    Label("Fetch example", systemImage: "text.book.closed")
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
                    // AVSpeechSynthesizer wired in Phase 6.
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
}
