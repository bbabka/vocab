import SwiftUI

/// Presented via `fullScreenCover` (not pushed onto a `NavigationStack`)
/// specifically so there is no edge-swipe-to-dismiss gesture competing with
/// the card's own left/right swipes — the brief's flagged real gesture risk
/// is the horizontal edge-swipe-back vs. a horizontal card swipe, not the
/// downward skip swipe, and presenting modally sidesteps it entirely rather
/// than needing to fight `interactivePopGesture` mid-session.
struct PracticeSessionView: View {
    let collectionId: UUID?
    let batchSize: Int

    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var batch: [Word] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var dragOffset: CGSize = .zero
    @State private var tally = SessionTally()
    @State private var isFinished = false

    private var currentWord: Word? {
        guard currentIndex < batch.count else { return nil }
        return batch[currentIndex]
    }

    private var nextWord: Word? {
        let nextIndex = currentIndex + 1
        guard nextIndex < batch.count else { return nil }
        return batch[nextIndex]
    }

    /// How far into the current drag/fly-off we are, 0...1. Drives the next
    /// card's fade/scale-in underneath — reusing `dragOffset` directly means
    /// it stays in sync automatically through both the live drag and the
    /// fly-off animation (SwiftUI interpolates `dragOffset`, so this
    /// recomputes on every frame of both), and snaps back to 0 for free when
    /// `finishCommit` resets `dragOffset` with animations disabled.
    private var dragProgress: CGFloat {
        let maxDistance: CGFloat = 150
        let magnitude = max(abs(dragOffset.width), abs(dragOffset.height))
        return min(magnitude / maxDistance, 1.0)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished || currentWord == nil {
                    PracticeSummaryView(tally: tally) { dismiss() }
                } else if let word = currentWord {
                    cardStack(for: word)
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { isFinished = true }
                }
            }
        }
        .onAppear {
            batch = wordStore.assembleBatch(collectionId: collectionId, batchSize: batchSize)
        }
    }

    @ViewBuilder
    private func cardStack(for word: Word) -> some View {
        VStack {
            Spacer()

            ZStack {
                // Revealed underneath as the current card is dragged away —
                // stacked-deck effect. Never flipped (it isn't current yet)
                // and ignores hit-testing so it can't steal the gesture.
                if let nextWord {
                    FlashcardView(word: nextWord, isFlipped: false, onSpeak: {})
                        .padding(.horizontal, 24)
                        .scaleEffect(0.94 + 0.06 * dragProgress)
                        .opacity(dragProgress)
                        .allowsHitTesting(false)
                }

                // Inset horizontally from the screen edges: even under a
                // modal presentation, keep the draggable hit region away
                // from the edges so it never overlaps an edge-originated
                // system gesture.
                FlashcardView(word: word, isFlipped: isFlipped, onSpeak: { speak(word) })
                    .padding(.horizontal, 24)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(dragGesture(for: word))
                    .onTapGesture { isFlipped.toggle() }
            }

            Spacer()

            Text("\(currentIndex + 1) / \(batch.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
    }

    private func dragGesture(for word: Word) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let swipe = resolveSwipe(value.translation)
                if let swipe {
                    flingOffScreen(swipe, for: word)
                } else {
                    withAnimation(.spring) { dragOffset = .zero }
                }
            }
    }

    private func speak(_ word: Word) {
        let languageCode = collectionStore.collections.first { $0.id == word.collectionId }?.targetLanguage ?? "en"
        SpeechService.shared.speak(word.term, languageCode: languageCode)
    }

    private func resolveSwipe(_ translation: CGSize) -> ReviewResult? {
        let threshold: CGFloat = 80
        if abs(translation.width) > abs(translation.height), abs(translation.width) > threshold {
            return translation.width > 0 ? .know : .dontKnow
        }
        if translation.height > threshold, abs(translation.height) > abs(translation.width) {
            return .skip
        }
        return nil
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
    private func flingOffScreen(_ swipe: ReviewResult, for word: Word) {
        withAnimation(.easeOut(duration: 0.3)) {
            dragOffset = flyOffTarget(for: swipe)
        } completion: {
            finishCommit(swipe, for: word)
        }
    }

    private func finishCommit(_ swipe: ReviewResult, for word: Word) {
        if let outcome = wordStore.applySwipe(swipe, to: word.id) {
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

private struct FlashcardView: View {
    let word: Word
    let isFlipped: Bool
    let onSpeak: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isFlipped {
                Text(word.translation).font(.title2)
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
            } else {
                Text(word.term).font(.largeTitle.bold())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(RoundedRectangle(cornerRadius: 20).fill(.background).shadow(radius: 6))
        .overlay(alignment: .topTrailing) {
            // A plain-style `Button` intercepts its own tap, so this never
            // also triggers the card's flip `onTapGesture` underneath it.
            Button(action: onSpeak) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    PracticeSessionView(collectionId: nil, batchSize: 10)
        .environmentObject(WordStore())
        .environmentObject(ReviewStore())
        .environmentObject(CollectionStore())
}
