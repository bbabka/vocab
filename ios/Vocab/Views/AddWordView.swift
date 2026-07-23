import SwiftUI
// The Translation framework's Sendable auditing lags Swift 6 strict
// concurrency (`TranslationSession` isn't fully annotated), which otherwise
// flags `session.translate(_:)` inside `.translationTask` as an unsafe
// cross-isolation send even though Apple's own usage pattern is exactly this.
@preconcurrency import Translation

struct AddWordView: View {
    let collectionId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var meanings: [WordMeaning] = [WordMeaning(translation: "")]
    @State private var exampleSentence = ""
    @State private var importance = 2

    @State private var translationState: TranslationFieldState = .checking
    @State private var configuration: TranslationSession.Configuration?

    private var collection: WordCollection? {
        collectionStore.collections.first { $0.id == collectionId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Term") {
                    TextField("Term", text: $term)
                }

                Section("Meanings") {
                    // The first row is auto-suggested by the Translation
                    // framework, debounced off `term` below; always editable
                    // and never blocks saving, even mid-translation or on a
                    // failure. Additional rows are entirely manual — Apple's
                    // Translation API returns one plain translation, not a
                    // dictionary of senses.
                    ForEach($meanings, editActions: .delete) { $meaning in
                        HStack {
                            Picker("Part of speech", selection: $meaning.partOfSpeech) {
                                ForEach(PartOfSpeech.allCases, id: \.self) { pos in
                                    Text(pos.abbreviation.isEmpty ? "—" : pos.abbreviation).tag(pos)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            TextField("Meaning", text: $meaning.translation)
                            if meaning.id == meanings.first?.id, translationState == .translating {
                                ProgressView()
                            }
                        }
                    }
                    Button {
                        meanings.append(WordMeaning(translation: ""))
                    } label: {
                        Label("Add meaning", systemImage: "plus")
                    }
                    if case .unsupported(let source, let target) = translationState {
                        Text("Auto-translate isn't available for \(source) → \(target) — enter manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                                meanings: meanings.filter { !$0.translation.isEmpty },
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
        .task {
            guard let collection else { return }
            translationState = await TranslationService.checkAvailability(from: collection.targetLanguage, to: collection.nativeLanguage)
        }
        // `.task(id:)` cancels and restarts on every keystroke, giving a free
        // debounce: only a `term` that's stayed put for 400ms triggers a
        // (re)translation. Also doubles as a fallback in case the on-appear
        // availability check hasn't resolved yet by the time typing starts.
        .task(id: term) {
            guard !term.isEmpty else { return }
            if translationState == .checking, let collection {
                translationState = await TranslationService.checkAvailability(from: collection.targetLanguage, to: collection.nativeLanguage)
            }
            if case .unsupported = translationState { return }

            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            if configuration == nil {
                configuration = TranslationSession.Configuration(
                    source: collection.map { Locale.Language(identifier: $0.targetLanguage) },
                    target: collection.map { Locale.Language(identifier: $0.nativeLanguage) }
                )
            } else {
                configuration?.invalidate()
            }
        }
        .translationTask(configuration) { session in
            guard !term.isEmpty, !meanings.isEmpty else { return }
            translationState = .translating
            do {
                let response = try await session.translate(term)
                meanings[0].translation = response.targetText
                translationState = .idle
            } catch {
                // Transient failure: leave the field as-is, silently, per
                // the brief — this is a suggestion, not a dependency.
                translationState = .idle
            }
        }
    }
}

#Preview {
    AddWordView(collectionId: MockData.spanishTravel.id)
        .environmentObject(WordStore())
        .environmentObject(CollectionStore())
}
