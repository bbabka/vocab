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

            // Inset horizontally from the screen edges: even under a modal
            // presentation, keep the draggable hit region away from the
            // edges so it never overlaps an edge-originated system gesture.
            FlashcardView(word: word, isFlipped: isFlipped)
                .padding(.horizontal, 24)
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                .gesture(dragGesture(for: word))
                .onTapGesture { isFlipped.toggle() }

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
                    commit(swipe, for: word)
                } else {
                    withAnimation(.spring) { dragOffset = .zero }
                }
            }
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

    private func commit(_ swipe: ReviewResult, for word: Word) {
        if let outcome = wordStore.applySwipe(swipe, to: word.id) {
            reviewStore.record(outcome)
        }
        tally.record(swipe)

        withAnimation(.spring) {
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
    }
}

#Preview {
    PracticeSessionView(collectionId: nil, batchSize: 10)
        .environmentObject(WordStore())
        .environmentObject(ReviewStore())
}
