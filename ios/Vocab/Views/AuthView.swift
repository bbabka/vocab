import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        NavigationStack {
            Form {
                if !codeSent {
                    Section("Sign in") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            Task {
                                await authStore.sendCode(email: email)
                                if authStore.errorMessage == nil {
                                    codeSent = true
                                }
                            }
                        } label: {
                            if authStore.isSendingCode {
                                ProgressView()
                            } else {
                                Text("Send Code")
                            }
                        }
                        .disabled(email.isEmpty || authStore.isSendingCode)
                    }
                } else {
                    Section("Enter Code") {
                        Text("We sent a 6-digit code to \(email).")
                            .foregroundStyle(.secondary)
                        TextField("Code", text: $code)
                            .keyboardType(.numberPad)
                        Button {
                            Task { await authStore.verifyCode(email: email, code: code) }
                        } label: {
                            if authStore.isVerifying {
                                ProgressView()
                            } else {
                                Text("Verify")
                            }
                        }
                        .disabled(code.isEmpty || authStore.isVerifying)

                        Button("Use a different email") {
                            codeSent = false
                            code = ""
                            authStore.errorMessage = nil
                        }
                    }
                }

                if let errorMessage = authStore.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Vocab")
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthStore())
}
