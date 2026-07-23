import SwiftUI

/// Sentinel `Picker` tag for "Other" — never a real language code (all of
/// `Language.common`'s are two letters), so it can't collide.
private let otherLanguageTag = "other"

struct AddCollectionView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var targetLanguageSelection = "es"
    @State private var nativeLanguageSelection = "en"
    @State private var customTargetLanguage = ""
    @State private var customNativeLanguage = ""

    /// `target_language`/`native_language` are free BCP-47 strings with no
    /// server-side validation (see `Language.swift`) — `Language.common` is
    /// only a curated convenience list, so "Other" just exposes that same
    /// freedom in the UI. Useful for a language Apple's Translation
    /// framework doesn't support yet (e.g. Danish, landing in a future iOS):
    /// add the collection now with manual entry, and once the pair becomes
    /// available, `TranslationService.checkAvailability` (a runtime check,
    /// not a hardcoded list) picks it up automatically — nothing to migrate.
    private var resolvedTargetLanguage: String {
        targetLanguageSelection == otherLanguageTag ? customTargetLanguage.trimmingCharacters(in: .whitespaces) : targetLanguageSelection
    }

    private var resolvedNativeLanguage: String {
        nativeLanguageSelection == otherLanguageTag ? customNativeLanguage.trimmingCharacters(in: .whitespaces) : nativeLanguageSelection
    }

    private var canCreate: Bool {
        guard !name.isEmpty else { return false }
        guard !resolvedTargetLanguage.isEmpty, !resolvedNativeLanguage.isEmpty else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Spanish — Travel", text: $name)
                }

                Section("Languages") {
                    Picker("Learning", selection: $targetLanguageSelection) {
                        ForEach(Language.common) { language in
                            Text(language.name).tag(language.code)
                        }
                        Text("Other…").tag(otherLanguageTag)
                    }
                    if targetLanguageSelection == otherLanguageTag {
                        TextField("Language code (e.g. da)", text: $customTargetLanguage)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Picker("Native", selection: $nativeLanguageSelection) {
                        ForEach(Language.common) { language in
                            Text(language.name).tag(language.code)
                        }
                        Text("Other…").tag(otherLanguageTag)
                    }
                    if nativeLanguageSelection == otherLanguageTag {
                        TextField("Language code (e.g. da)", text: $customNativeLanguage)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        collectionStore.add(
                            WordCollection(name: name, targetLanguage: resolvedTargetLanguage, nativeLanguage: resolvedNativeLanguage)
                        )
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }
}

#Preview {
    AddCollectionView()
        .environmentObject(CollectionStore())
}
