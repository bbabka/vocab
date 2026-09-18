import SwiftUI

/// Shared "Add definition" control for the Meanings section in both
/// `AddWordView` and `WordDetailView` — mirrors `ExampleFetchButton`'s
/// shape, but fetches a same-language explanation (e.g. an English word's
/// English definition) via the on-device FoundationModels LLM and hands it
/// back as an ordinary `WordMeaning`, exactly like a manually typed or
/// auto-translated one — it's just another row, not a separate field.
/// Gated at iOS 26+ along with `DefinitionService`; call sites wrap their
/// usage in `if #available(iOS 26, *)`.
@available(iOS 26.0, *)
struct DefinitionFetchButton: View {
    let term: String
    let languageCode: String
    let onFetched: (String) -> Void

    @State private var availability: DefinitionAvailability = .checking
    @State private var isFetching = false
    @State private var fetchFailed = false

    var body: some View {
        Group {
            // Unlike `ExampleFetchButton` (always offered) or the
            // translate-on-type flow's `.unsupported` case (a persistent
            // inline message), an ineligible/Apple-Intelligence-off device
            // just doesn't get this button — there's nothing to retry.
            if availability != .unavailable {
                Button {
                    Task { await fetchDefinition() }
                } label: {
                    if isFetching {
                        ProgressView()
                    } else {
                        Label("Add definition", systemImage: "character.book.closed")
                    }
                }
                .disabled(isFetching || availability == .checking || term.isEmpty)
                if fetchFailed {
                    Text("Couldn't fetch a definition — try again or enter one manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            availability = DefinitionService.checkAvailability()
        }
    }

    private func fetchDefinition() async {
        guard !term.isEmpty else { return }
        isFetching = true
        defer { isFetching = false }

        if let definition = await DefinitionService.fetchDefinition(term: term, language: languageCode) {
            onFetched(definition)
            fetchFailed = false
        } else {
            fetchFailed = true
        }
    }
}
