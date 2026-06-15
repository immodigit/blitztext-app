import Foundation

/// Bilanz-Text für einen Stapel-Transkriptions-Lauf — reine, testbare Logik.
public enum TranscriptionBatchSummary {
    /// Liefert eine kurze Bilanz, sofern mindestens eine Datei fehlschlug;
    /// sonst `nil` (dann gibt es nichts zu melden).
    public static func text(succeeded: Int, failures: [String]) -> String? {
        guard !failures.isEmpty else { return nil }
        let header = "\(succeeded) erfolgreich, \(failures.count) fehlgeschlagen:"
        let lines = failures.map { "• \($0)" }.joined(separator: "\n")
        return "\(header)\n\(lines)"
    }
}
