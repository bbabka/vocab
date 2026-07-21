import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore

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
                    Task { await authStore.signOut() }
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
}
