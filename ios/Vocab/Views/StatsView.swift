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
                HeatmapView(
                    grid: HeatmapBuilder.grid(activity: reviewStore.dailyActivity, weeks: 12, today: CalendarDay(date: Date()))
                )
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Stats")
        .refreshable {
            async let words: () = wordStore.loadFromRemote()
            async let reviews: () = reviewStore.loadFromRemote()
            _ = await (words, reviews)
        }
    }
}

private struct HeatmapView: View {
    let grid: [[HeatmapCell?]]

    private func color(for count: Int) -> Color {
        switch count {
        case 0: .secondary.opacity(0.12)
        case 1...2: .accentColor.opacity(0.35)
        case 3...5: .accentColor.opacity(0.6)
        case 6...9: .accentColor.opacity(0.85)
        default: .accentColor
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(grid.indices, id: \.self) { column in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { row in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(grid[column][row].map { color(for: $0.reviewsCount) } ?? Color.clear)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
    .environmentObject(WordStore())
    .environmentObject(ReviewStore())
}
