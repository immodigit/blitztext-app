import Foundation
import FoundationModels

/// Lokale Textumformung über Apples on-device Foundation Model (macOS 26+).
/// Läuft vollständig auf dem Gerät — kein Netzwerk, keine Cloud.
enum AppleFoundationRewriter {
    /// True, wenn das on-device Modell einsatzbereit ist
    /// (macOS 26+, Apple Intelligence aktiv, Gerät geeignet, Modell geladen).
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// Lesbarer Grund, falls nicht verfügbar (für UI/Diagnose).
    static var unavailableReason: String? {
        guard #available(macOS 26.0, *) else {
            return "Benötigt macOS 26 oder neuer."
        }
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

    /// Formt den Text on-device um. `instructions` entspricht dem System-Prompt.
    @available(macOS 26.0, *)
    static func rewrite(text: String, instructions: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
