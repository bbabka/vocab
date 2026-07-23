import SwiftUI

private enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case new = "New"
    case learning = "Learning"
    case learnt = "Learnt"

    var id: String { rawValue }

    var status: WordStatus? {
        switch self {
        case .all: return nil
        case .new: return .new
        case .learning: return .learning
        case .learnt: return .learnt
        }
    }
}

struct WordListView: View {
    let collectionId: UUID

    @EnvironmentObject private var wordStore: WordStore
    @State private var filter: StatusFilter = .all
    @State private var searchText = ""
    @State private var isPresentingAddWord = false

    private var filteredWords: [Word] {
        var result = wordStore.words(in: collectionId)
        if let status = filter.status {
            result = result.filter { $0.status == status }
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
                    WordRow(word: word)
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

    private var meaningsSummary: String {
        word.meanings
            .map { $0.partOfSpeech.abbreviation.isEmpty ? $0.translation : "\($0.partOfSpeech.abbreviation) \($0.translation)" }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(word.term).font(.body)
                if !word.meanings.isEmpty {
                    Text(meaningsSummary).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusBadge(status: word.status)
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
