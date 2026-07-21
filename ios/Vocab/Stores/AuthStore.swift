import Foundation
import Supabase

/// Email OTP via code entry, deliberately not magic-link: the brief chose
/// this specifically to avoid needing Associated Domains/Universal Links
/// entitlements for a TestFlight-only personal build. The Supabase email
/// template (`supabase/templates/magic_link.html`) is customized to show
/// the raw `{{ .Token }}` so there's a code to type — the default template
/// only shows a link, which this app never registers a URL scheme to catch.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published var isSendingCode = false
    @Published var isVerifying = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Restores any existing session on launch, then keeps `session` in
    /// sync with subsequent sign-in/sign-out/token-refresh events. Runs for
    /// the lifetime of the app (called from a long-lived `.task`).
    func observeAuthState() async {
        for await state in client.auth.authStateChanges {
            session = state.session
        }
    }

    func sendCode(email: String) async {
        isSendingCode = true
        errorMessage = nil
        defer { isSendingCode = false }
        do {
            try await client.auth.signInWithOTP(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func verifyCode(email: String, code: String) async {
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            session = response.session
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        session = nil
    }
}
