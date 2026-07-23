import SwiftUI

/// Shared "Fetch example" control for the Example section in both
/// `AddWordView` and `WordDetailView` — same button, spinner, and
/// best-effort-failure note; call sites just supply the term/language pair
/// and receive the fetched sentence via `onFetched`.
struct ExampleFetchButton: View {
    let term: String
    let languageCode: String
    let nativeLanguageCode: String
    let onFetched: (String) -> Void

    @State private var isFetching = false
    @State private var fetchFailed = false

    var body: some View {
        Group {
            Button {
                Task { await fetchExample() }
            } label: {
                if isFetching {
                    ProgressView()
                } else {
                    Label("Fetch example", systemImage: "text.book.closed")
                }
            }
            .disabled(isFetching || term.isEmpty)
            if fetchFailed {
                // Best-effort, undocumented endpoint (see brief) — a
                // non-blocking, dismissible-by-retry note, never an alert.
                Text("Couldn't fetch an example — try again or enter one manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fetchExample() async {
        guard !term.isEmpty else { return }
        isFetching = true
        defer { isFetching = false }

        if let example = await TatoebaService.fetchExample(
            term: term,
            languageCode: languageCode,
            nativeLanguageCode: nativeLanguageCode
        ) {
            onFetched(example)
            fetchFailed = false
        } else {
            fetchFailed = true
        }
    }
}
