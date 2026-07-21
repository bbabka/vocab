import Foundation

/// Distinct wrapper types for `navigationDestination(for:)` routing.
///
/// Both Collections and Word List push a bare `UUID` value — using `UUID`
/// itself as the route type is a SwiftUI pitfall: with two
/// `.navigationDestination(for: UUID.self)` modifiers in the same
/// `NavigationStack` (one in `CollectionsListView`, one in `WordListView`),
/// SwiftUI resolves *any* pushed `UUID` — collection or word — to whichever
/// destination is declared higher in the stack, so tapping a word could
/// silently reuse the Collections→WordList destination with the word's id
/// misread as a collection id. Wrapping each id in its own `Hashable` type
/// makes the two routes unambiguous.
struct CollectionRoute: Hashable {
    let id: UUID
}

struct WordRoute: Hashable {
    let id: UUID
}
