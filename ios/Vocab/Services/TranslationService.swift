import Foundation
import Translation

/// The three user-visible states an auto-translate field can be in — kept
/// visually distinct per the brief: a spinner while translating, a silent
/// blank/manual field on a transient failure, and a permanent inline message
/// for a genuinely unsupported language pair. Without this distinction, an
/// unsupported pair (e.g. da→en, unavailable until iOS 27) would look
/// identical to "still loading" — a spinner that never resolves.
enum TranslationFieldState: Equatable {
    case checking
    case translating
    case idle
    case unsupported(source: String, target: String)
}

enum TranslationService {
    /// Checks device-reported availability at runtime rather than trusting
    /// documentation of Apple's supported-language list, which drifts and
    /// lags real device/OS rollout. `target_language`/`native_language` are
    /// free BCP-47 strings with no validation (see `Language.swift`), so any
    /// pair can reach this check at any time.
    static func checkAvailability(from source: String, to target: String) async -> TranslationFieldState {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target)
        )
        switch status {
        case .installed, .supported:
            return .idle
        case .unsupported:
            return .unsupported(source: source, target: target)
        @unknown default:
            return .unsupported(source: source, target: target)
        }
    }
}
