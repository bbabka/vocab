import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore

    private struct WordCounts {
        var total: Int
        var learnt: Int
        var learning: Int
        var new: Int
    }

    private var counts: WordCounts {
        let words = wordStore.words
        let learntCount = words.filter { $0.status == .learnt || $0.status == .retired }.count
        let learningCount = words.filter { $0.status == .learning }.count
        let newCount = words.filter { $0.status == .new }.count
        return WordCounts(total: words.count, learnt: learntCount, learning: learningCount, new: newCount)
    }

    var body: some View {
        List {
            Section("Streak") {
                LabeledContent("Current streak", value: "\(reviewStore.currentStreak()) days")
                LabeledContent("Longest streak", value: "\(reviewStore.longestStreak()) days")
            }

            Section("Words") {
                LabeledContent("Total", value: "\(counts.total)")
                LabeledContent("New", value: "\(counts.new)")
                LabeledContent("Learning", value: "\(counts.learning)")
                LabeledContent("Learnt", value: "\(counts.learnt)")
            }

            Section("Activity") {
                ForEach(reviewStore.dailyActivity.sorted(by: { $0.activityDate > $1.activityDate }), id: \.activityDate) { activity in
                    LabeledContent(
                        "\(activity.activityDate.year)-\(activity.activityDate.month)-\(activity.activityDate.day)",
                        value: "\(activity.reviewsCount) reviews"
                    )
                }
            }
        }
        .navigationTitle("Stats")
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
    .environmentObject(WordStore())
    .environmentObject(ReviewStore())
}
