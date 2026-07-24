import Foundation
// FoundationModels gibt es erst ab macOS 26 / Xcode 26. Auf älteren Toolchains
// (z. B. GitHub-CI mit Xcode 16) fehlt das Modul komplett — deshalb bedingt
// importieren, sonst schlägt schon die Modul-Auflösung fehl.
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Lokale Textumformung über Apples on-device Foundation Model (macOS 26+).
/// Läuft vollständig auf dem Gerät — kein Netzwerk, keine Cloud.
///
/// Wird das Framework beim Bauen nicht gefunden (altes SDK), bleibt die API
/// erhalten, meldet aber „nicht verfügbar" — die Aufrufer kompilieren und
/// fallen zur Laufzeit sauber auf andere Umform-Backends zurück.
enum AppleFoundationRewriter {
    enum RewriterError: Error {
        /// Zur Build-Zeit war FoundationModels nicht verfügbar.
        case frameworkUnavailable
    }

    /// True, wenn das on-device Modell einsatzbereit ist
    /// (macOS 26+, Apple Intelligence aktiv, Gerät geeignet, Modell geladen).
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Lesbarer Grund, falls nicht verfügbar (für UI/Diagnose).
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "Dieses Gerät unterstützt Apple Intelligence nicht."
                case .appleIntelligenceNotEnabled:
                    return "Apple Intelligence ist nicht aktiviert (Systemeinstellungen)."
                case .modelNotReady:
                    return "Das lokale Modell wird noch geladen."
                @unknown default:
                    return "Lokales Modell nicht verfügbar."
                }
            }
        }
        return "Benötigt macOS 26 oder neuer."
        #else
        return "Benötigt macOS 26 oder neuer (in diesem Build nicht einkompiliert)."
        #endif
    }

    /// Formt den Text on-device um. `instructions` entspricht dem System-Prompt.
    @available(macOS 26.0, *)
    static func rewrite(text: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        // Build ohne FoundationModels-SDK: Pfad ist zur Laufzeit nie aktiv,
        // weil isAvailable dann false liefert.
        throw RewriterError.frameworkUnavailable
        #endif
    }
}
