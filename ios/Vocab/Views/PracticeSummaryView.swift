import SwiftUI

struct PracticeSummaryView: View {
    let tally: SessionTally
    let onDone: () -> Void

    @EnvironmentObject private var reviewStore: ReviewStore

    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("hasPromptedForReminder") private var hasPromptedForReminder = false
    @AppStorage("reminderHour") private var reminderHour = 19
    @AppStorage("reminderMinute") private var reminderMinute = 0

    /// Prompt only once, ever, and only if reminders aren't already on —
    /// the brief calls for requesting notification permission contextually
    /// after a first successful session, never at cold launch.
    private var shouldPromptForReminder: Bool {
        !reminderEnabled && !hasPromptedForReminder
    }

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

            if shouldPromptForReminder {
                reminderPrompt
            }

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .task {
            // A repeating notification's content is fixed at schedule time,
            // so refresh it after every session to keep the streak count
            // in the body from going stale.
            if reminderEnabled {
                NotificationScheduler.shared.scheduleDailyReminder(
                    hour: reminderHour, minute: reminderMinute, streak: reviewStore.currentStreak()
                )
            }
        }
    }

    private var reminderPrompt: some View {
        VStack(spacing: 8) {
            Text("Want a daily reminder to keep your streak going?")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Not now") { hasPromptedForReminder = true }
                Button("Enable") {
                    hasPromptedForReminder = true
                    Task {
                        let granted = await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                        if granted {
                            reminderEnabled = true
                            NotificationScheduler.shared.scheduleDailyReminder(
                                hour: reminderHour, minute: reminderMinute, streak: reviewStore.currentStreak()
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
