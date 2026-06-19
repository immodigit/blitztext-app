import Foundation

/// Bereinigt Umform-Ausgaben kleiner lokaler Modelle: entfernt typische
/// Vorreden ("Hier ist der verbesserte Text:") und umschließende
/// Anführungszeichen. Reine, testbare Logik.
public enum LocalRewriteSanitizer {
    // Führende Meta-Einleitung: Schlüsselphrase + kurzer Text + Doppelpunkt.
    private static let preamblePattern =
        #"(?i)^\s*(hier ist|here is|here's|verbesserter text|überarbeiteter text|improved text)[^\n:]{0,60}:\s*"#

    public static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = result.range(of: preamblePattern, options: .regularExpression) {
            result.removeSubrange(range)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return strippingWrappingQuotes(result)
    }

    private static func strippingWrappingQuotes(_ value: String) -> String {
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("\u{201E}", "\u{201C}"), // „ … "
            ("\u{201C}", "\u{201D}"), // " … "
            ("'", "'"),
        ]
        for (open, close) in pairs where value.count >= 2 && value.first == open && value.last == close {
            return String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}
