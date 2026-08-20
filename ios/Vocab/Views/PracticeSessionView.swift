import SwiftUI

/// Presented via `fullScreenCover` (not pushed onto a `NavigationStack`)
/// specifically so there is no edge-swipe-to-dismiss gesture competing with
/// the card's own left/right swipes — presenting modally sidesteps the
/// horizontal edge-swipe-back vs. horizontal card swipe conflict entirely
/// rather than needing to fight `interactivePopGesture` mid-session.
struct PracticeSessionView: View {
    let collectionIds: Set<UUID>?
    let batchSize: Int
    let direction: PracticeDirection

    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var batch: [PracticeCard] = []
    @State private var hasLoadedBatch = false
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var dragOffset: CGSize = .zero
    @State private var tally = SessionTally()
    @State private var isFinished = false

    /// True only once `assembleBatch` has actually run and come back empty —
    /// distinct from `isFinished`, which means a session was swiped through
    /// to completion. Without this, a session that never had any eligible
    /// cards (e.g. recall before any word has unlocked it) fell into the
    /// exact same "Session Complete" screen as a real finished session,
    /// showing a misleading 0/0/0 tally instead of explaining why there's
    /// nothing to review.
    private var isEmptyFromTheStart: Bool {
        hasLoadedBatch && !isFinished && currentCard == nil
    }

    private var currentCard: PracticeCard? {
        guard currentIndex < batch.count else { return nil }
        return batch[currentIndex]
    }

    private var nextCard: PracticeCard? {
        let nextIndex = currentIndex + 1
        guard nextIndex < batch.count else { return nil }
        return batch[nextIndex]
    }

    /// How far into the current drag/fly-off we are, 0...1. Drives the next
    /// card's fade/scale-in underneath and the background tint's color/
    /// intensity — one signed value for both, since `dragOffset` is
    /// horizontal-only (skip is a button, not a drag direction, so there's
    /// no vertical component to account for separately). Reusing
    /// `dragOffset` directly means it stays in sync automatically through
    /// both the live drag and the fly-off animation (SwiftUI interpolates
    /// `dragOffset`, so this recomputes on every frame of both), and snaps
    /// back to 0 for free when `finishCommit` resets `dragOffset` with
    /// animations disabled. Range -1...1: positive for a rightward ("know")
    /// drag, negative for leftward ("don't know").
    private var dragProgress: CGFloat {
        let maxDistance: CGFloat = 150
        return max(min(dragOffset.width / maxDistance, 1.0), -1.0)
    }

    private var swipeTintColor: Color {
        dragProgress >= 0 ? .green : .red
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoadedBatch {
                    ProgressView()
                } else if isEmptyFromTheStart {
                    emptyState
                } else if isFinished || currentCard == nil {
                    PracticeSummaryView(tally: tally) { dismiss() }
                } else if let card = currentCard {
                    cardStack(for: card)
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEmptyFromTheStart {
                        Button("Done") { dismiss() }
                    } else {
                        Button("End") { isFinished = true }
                    }
                }
            }
        }
        // `.task`, not `.onAppear`: a session used to assemble its batch
        // straight from whatever `wordStore` already had in memory, which
        // is stale the moment something changed server-side since the last
        // fetch/Realtime event landed — e.g. a manual status override in
        // Word Detail unlocks a new `recall` progress row server-side (via
        // the DB trigger), but the client only learns about that new row
        // through a fresh fetch or Realtime, neither of which a plain
        // in-memory `assembleBatch` call waits for. Refreshing here means a
        // session always starts from a real fetch, not a hopeful cache read.
        .task {
            await wordStore.loadFromRemote()
            batch = wordStore.assembleBatch(collectionIds: collectionIds, direction: direction, batchSize: batchSize)
            hasLoadedBatch = true
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to Review", systemImage: "checkmark.circle")
        } description: {
            Text(emptyStateMessage)
        }
    }

    private var emptyStateMessage: String {
        switch direction {
        case .recognize:
            "You're all caught up — nothing due right now."
        case .recall:
            "No words are ready for recall practice yet. Recall unlocks for a word once you've learnt it by recognizing it — keep practicing Recognize."
        }
    }

    @ViewBuilder
    private func cardStack(for card: PracticeCard) -> some View {
        VStack {
            Spacer()

            ZStack {
                // Revealed underneath as the current card is dragged away —
                // stacked-deck effect. Never flipped (it isn't current yet)
                // and ignores hit-testing so it can't steal the gesture.
                if let nextCard {
                    FlashcardView(word: nextCard.word, direction: direction, isFlipped: false, onSpeak: {})
                        .padding(.horizontal, 24)
                        .scaleEffect(0.94 + 0.06 * abs(dragProgress))
                        .opacity(abs(dragProgress))
                        .allowsHitTesting(false)
                }

                // Inset horizontally from the screen edges: even under a
                // modal presentation, keep the draggable hit region away
                // from the edges so it never overlaps an edge-originated
                // system gesture.
                FlashcardView(word: card.word, direction: direction, isFlipped: isFlipped, onSpeak: { speak(card.word) })
                    .padding(.horizontal, 24)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(dragGesture(for: card))
                    .onTapGesture { isFlipped.toggle() }
            }

            Spacer()

            Text("\(currentIndex + 1) / \(batch.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .background(
            swipeTintColor
                .opacity(Double(abs(dragProgress)) * 0.6)
                .ignoresSafeArea()
        )
        .overlay(alignment: .bottomTrailing) {
            skipButton(for: card)
        }
    }

    /// Explicit tap target for skip, replacing the old downward-drag
    /// gesture — keeps `dragOffset` purely horizontal so the background
    /// tint and `resolveSwipe`'s classification read from the same value
    /// and can never disagree.
    private func skipButton(for card: PracticeCard) -> some View {
        Button {
            flingOffScreen(.skip, for: card)
        } label: {
            Label("Skip", systemImage: "arrow.uturn.right")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(14)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(20)
    }

    private func dragGesture(for card: PracticeCard) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Horizontal-only: skip is now a button, not a drag
                // direction, so vertical motion shouldn't move the card.
                dragOffset = CGSize(width: value.translation.width, height: 0)
            }
            .onEnded { value in
                let swipe = resolveSwipe(value.translation.width)
                if let swipe {
                    flingOffScreen(swipe, for: card)
                } else {
                    withAnimation(.spring) { dragOffset = .zero }
                }
            }
    }

    private func speak(_ word: Word) {
        let languageCode = collectionStore.collections.first { $0.id == word.collectionId }?.targetLanguage ?? "en"
        SpeechService.shared.speak(word.term, languageCode: languageCode)
    }

    private func resolveSwipe(_ horizontalTranslation: CGFloat) -> ReviewResult? {
        let threshold: CGFloat = 80
        guard abs(horizontalTranslation) > threshold else { return nil }
        return horizontalTranslation > 0 ? .know : .dontKnow
    }

    /// Distance is deliberately larger than any device's screen dimension so
    /// the card is fully clear of the visible bounds by the time the fly-off
    /// animation finishes, regardless of device size.
    private func flyOffTarget(for swipe: ReviewResult) -> CGSize {
        let distance: CGFloat = 1200
        switch swipe {
        case .know: return CGSize(width: distance, height: 0)
        case .dontKnow: return CGSize(width: -distance, height: 0)
        case .skip: return CGSize(width: 0, height: distance)
        }
    }

    /// Animates the current card fully off-screen — Tinder-style, no
    /// bounce-back — while it still shows the *outgoing* word (`currentIndex`
    /// doesn't change yet). Only once that animation finishes does
    /// `finishCommit` advance to the next word, and it does so with
    /// animations disabled: the previous bug had the index advance in the
    /// same animated block as the offset reset, so the still-mid-flight card
    /// would already be showing the *next* word's text — the new text and
    /// the departing card visually clashed. Separating "animate out" from
    /// "swap content, then snap in" fixes that.
    private func flingOffScreen(_ swipe: ReviewResult, for card: PracticeCard) {
        withAnimation(.easeOut(duration: 0.3)) {
            dragOffset = flyOffTarget(for: swipe)
        } completion: {
            finishCommit(swipe, for: card)
        }
    }

    private func finishCommit(_ swipe: ReviewResult, for card: PracticeCard) {
        if let outcome = wordStore.applySwipe(swipe, to: card.word.id, direction: direction) {
            reviewStore.record(outcome)
        }
        tally.record(swipe)

        // No animation here on purpose: the next card should simply be
        // there at center already showing its own text, not visibly slide
        // in from off-screen after the previous one just left.
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) {
            dragOffset = .zero
            isFlipped = false
            currentIndex += 1
        }

        if currentIndex >= batch.count {
            isFinished = true
        }
    }
}

struct SessionTally {
    var known = 0
    var dontKnow = 0
    var skipped = 0

    mutating func record(_ result: ReviewResult) {
        switch result {
        case .know: known += 1
        case .dontKnow: dontKnow += 1
        case .skip: skipped += 1
        }
    }
}

/// `.recognize`: front is `term`, back reveals meanings/example/pronunciation
/// — unchanged from pre-Recall-Layer behavior. `.recall`: front/back flip —
/// meanings are the prompt, `term` is the answer. The speaker button is
/// hidden on the recall front: `term` isn't shown yet there, so speaking it
/// would hand the user the answer before they've attempted to produce it.
private struct FlashcardView: View {
    let word: Word
    let direction: PracticeDirection
    let isFlipped: Bool
    let onSpeak: () -> Void

    private var showsSpeaker: Bool {
        direction == .recognize || isFlipped
    }

    var body: some View {
        VStack(spacing: 12) {
            switch direction {
            case .recognize:
                if isFlipped {
                    meanings
                    exampleAndPronunciation
                } else {
                    Text(word.term).font(.largeTitle.bold())
                }
            case .recall:
                if isFlipped {
                    Text(word.term).font(.largeTitle.bold())
                    exampleAndPronunciation
                } else {
                    meanings
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(RoundedRectangle(cornerRadius: 20).fill(.background).shadow(radius: 6))
        .overlay(alignment: .topTrailing) {
            // A plain-style `Button` intercepts its own tap, so this never
            // also triggers the card's flip `onTapGesture` underneath it.
            if showsSpeaker {
                Button(action: onSpeak) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var meanings: some View {
        ForEach(word.meanings) { meaning in
            HStack(spacing: 6) {
                if !meaning.partOfSpeech.abbreviation.isEmpty {
                    Text(meaning.partOfSpeech.abbreviation)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                Text(meaning.translation)
            }
            .font(.title2)
        }
    }

    @ViewBuilder
    private var exampleAndPronunciation: some View {
        if let exampleSentence = word.exampleSentence {
            Text(exampleSentence)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        if let pronunciation = word.pronunciation {
            Text(pronunciation)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    PracticeSessionView(collectionIds: nil, batchSize: 10, direction: .recognize)
        .environmentObject(WordStore())
        .environmentObject(ReviewStore())
        .environmentObject(CollectionStore())
}
