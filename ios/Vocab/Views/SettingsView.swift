import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var wordStore: WordStore
    @EnvironmentObject private var reviewStore: ReviewStore

    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 19
    @AppStorage("reminderMinute") private var reminderMinute = 0

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? 19
                reminderMinute = components.minute ?? 0
                NotificationScheduler.shared.scheduleDailyReminder(
                    hour: reminderHour, minute: reminderMinute, streak: reviewStore.currentStreak()
                )
            }
        )
    }

    var body: some View {
        List {
            Section("Reminders") {
                Toggle("Daily reminder", isOn: Binding(
                    get: { reminderEnabled },
                    set: { isOn in
                        reminderEnabled = isOn
                        if isOn {
                            Task {
                                let granted = await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                                if granted {
                                    NotificationScheduler.shared.scheduleDailyReminder(
                                        hour: reminderHour, minute: reminderMinute, streak: reviewStore.currentStreak()
                                    )
                                } else {
                                    reminderEnabled = false
                                }
                            }
                        } else {
                            NotificationScheduler.shared.cancelDailyReminder()
                        }
                    }
                ))
                if reminderEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            }
            Section("Account") {
                if let email = authStore.session?.user.email {
                    Text(email)
                        .foregroundStyle(.secondary)
                }
                Button("Sign Out", role: .destructive) {
                    Task {
                        // Opportunistic sync attempt before signing out —
                        // `authStore.signOut()` refuses (with an error
                        // message below) if anything's still queued
                        // afterward, rather than silently discarding it.
                        await wordStore.drainOutbox()
                        await authStore.signOut()
                    }
                }
                if let errorMessage = authStore.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AuthStore())
    .environmentObject(WordStore())
    .environmentObject(ReviewStore())
}
