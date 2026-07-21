import SwiftUI

struct PracticeSummaryView: View {
    let tally: SessionTally
    let onDone: () -> Void

    @EnvironmentObject private var reviewStore: ReviewStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Session Complete")
                .font(.title2.bold())

            HStack(spacing: 32) {
                StatColumn(label: "Known", value: tally.known)
                StatColumn(label: "Didn't Know", value: tally.dontKnow)
                StatColumn(label: "Skipped", value: tally.skipped)
            }

            Text("Streak: \(reviewStore.currentStreak()) days")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct StatColumn: View {
    let label: String
    let value: Int

    var body: some View {
        VStack {
            Text("\(value)").font(.title.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PracticeSummaryView(tally: SessionTally(known: 8, dontKnow: 2, skipped: 1), onDone: {})
        .environmentObject(ReviewStore())
}
