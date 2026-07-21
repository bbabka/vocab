import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("Reminders") {
                Text("Daily reminder time — wired in Phase 7")
                    .foregroundStyle(.secondary)
            }
            Section("Account") {
                Text("Sign-in — wired in Phase 2")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
