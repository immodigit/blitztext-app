import Foundation

/// Reine, UI-freie Validierung des OpenAI API Keys — bewusst ausgelagert,
/// damit sie ohne AppKit/SwiftUI unit-getestet werden kann.
public enum OpenAIKeyValidator {
    public static let pattern = #"^sk-[A-Za-z0-9_-]{20,}$"#

    /// True, wenn die (getrimmte) Eingabe wie ein OpenAI API Key aussieht.
    public static func isPlausible(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Bestimmt einen kollisionsfreien Ziel-Dateinamen für ein Transkript.
/// Die Dateisystem-Abfrage wird injiziert, damit die Logik ohne echtes
/// Dateisystem testbar ist.
public enum TranscriptFileNaming {
    /// Liefert `<base>.txt` im Verzeichnis; existiert das schon, wird
    /// `<base>-1.txt`, `<base>-2.txt`, … gewählt — es wird nie überschrieben.
    public static func uniqueURL(
        forBase base: String,
        ext: String = "txt",
        in directory: URL,
        fileExists: (URL) -> Bool
    ) -> URL {
        var target = directory.appendingPathComponent("\(base).\(ext)")
        var index = 1
        while fileExists(target) {
            target = directory.appendingPathComponent("\(base)-\(index).\(ext)")
            index += 1
        }
        return target
    }
}
