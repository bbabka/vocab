import SwiftUI

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

private enum StatusFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case new = "New"
    case learning = "Learning"
    case learnt = "Learnt"
    case all = "All"

    var id: String { rawValue }

    var statuses: Set<WordStatus>? {
        switch self {
        case .all: return nil
        case .active: return [.new, .learning]
        case .new: return [.new]
        case .learning: return [.learning]
        case .learnt: return [.learnt]
        }
    }
}

struct WordListView: View {
    let collectionId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @State private var filter: StatusFilter = .active
    @State private var searchText = ""
    @State private var isPresentingAddWord = false

    /// Takes the status lookup as a parameter rather than reading
    /// `wordStore.recognizeStatusByWordId` itself — that's an O(n) rebuild
    /// over every progress row in the account, and `body` already needs the
    /// same dictionary for `WordRow`'s status badge, so it's computed once
    /// there and passed down instead of twice per render.
    private func filteredWords(statusByWordId: [UUID: WordStatus]) -> [Word] {
        var result = wordStore.words(in: collectionId)
        if let statuses = filter.statuses {
            result = result.filter { statuses.contains(statusByWordId[$0.id] ?? .new) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.term.localizedCaseInsensitiveContains(searchText)
                    || $0.meanings.contains { $0.translation.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result
    }

    var body: some View {
        let recognizeStatusByWordId = wordStore.recognizeStatusByWordId
        let filteredWords = filteredWords(statusByWordId: recognizeStatusByWordId)
        List {
            Picker("Filter", selection: $filter) {
                ForEach(StatusFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            ForEach(filteredWords) { word in
                NavigationLink(value: WordRoute(id: word.id)) {
                    WordRow(word: word, status: recognizeStatusByWordId[word.id] ?? .new)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    wordStore.delete(filteredWords[index].id)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Words")
        .navigationDestination(for: WordRoute.self) { route in
            WordDetailView(wordId: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddWord = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddWord) {
            AddWordView(collectionId: collectionId)
        }
    }
}

private struct WordRow: View {
    let word: Word
    let status: WordStatus

    private var meaningsSummary: Text {
        let entries = word.meanings.map { meaning -> Text in
            let translation = Text(meaning.translation.capitalizedFirstLetter)
            guard !meaning.partOfSpeech.abbreviation.isEmpty else { return translation }
            return Text(meaning.partOfSpeech.abbreviation).italic() + Text(" ") + translation
        }
        return entries.dropFirst().reduce(entries[0]) { partial, next in
            partial + Text(" · ") + next
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(word.term.capitalizedFirstLetter).font(.body)
                if !word.meanings.isEmpty {
                    meaningsSummary.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusBadge(status: status)
            ImportanceDots(importance: word.importance)
        }
    }
}

struct StatusBadge: View {
    let status: WordStatus

    private var color: Color {
        switch status {
        case .new: return .blue
        case .learning: return .orange
        case .learnt: return .green
        case .retired: return .gray
        }
    }

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct ImportanceDots: View {
    let importance: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < importance ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WordListView(collectionId: MockData.spanishTravel.id)
    }
    .environmentObject(WordStore())
}
