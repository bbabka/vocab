import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var wordStore: WordStore

    var body: some View {
        List {
            Section("Reminders") {
                Text("Daily reminder time — wired in Phase 7")
                    .foregroundStyle(.secondary)
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
}
