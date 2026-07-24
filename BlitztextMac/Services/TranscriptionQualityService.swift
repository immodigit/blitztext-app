import Foundation

enum TranscriptionQualityService {
    static let minimumRecordingDuration: TimeInterval = 0.3

    static func shouldRejectRecording(duration: TimeInterval) -> Bool {
        duration < minimumRecordingDuration
    }

    static func cleanedTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return strippingHallucinations(from: trimmed)
    }

    static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
        let cleaned = cleanedTranscript(text)
        guard !cleaned.isEmpty else { return true }

        let words = cleaned.split { $0.isWhitespace || $0.isNewline }
        let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        if letters == 0 {
            return true
        }

        if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
            return true
        }

        if recordingDuration < 0.8 && cleaned.count >= 56 {
            return true
        }

        return false
    }

    // MARK: - Whisper-Halluzinationen

    /// Whisper (v. a. die OpenAI-API) erfindet in Still-Phasen — etwa nach dem
    /// letzten gesprochenen Wort, während man die Aufnahmetaste noch hält —
    /// typische Füllsätze: Höflichkeitsfloskeln ("Vielen Dank.") und
    /// Untertitel-Credits ("Untertitelung des ZDF …"). Diese werden hier
    /// entfernt, wenn sie als eigener Schlusssatz oder als Gesamttext stehen.
    ///
    /// Bewusst konservativ: Nur ein exakt passender, eigenständiger Schlusssatz
    /// wird gekappt — Floskeln mitten im Satz bleiben unangetastet. Dadurch
    /// bleibt das Risiko klein, dass ein echt gesprochenes "Vielen Dank." am
    /// Ende verloren geht (Restrisiko, siehe Phrasenliste zum Nachjustieren).
    static func strippingHallucinations(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Mehrfach anwenden: Whisper hängt manchmal zwei Floskeln hintereinander.
        var didStrip = true
        while didStrip {
            didStrip = false
            guard !result.isEmpty else { break }

            let (head, tail) = splitLastSentence(result)
            if normalizedHallucinations.contains(normalize(tail)) {
                result = head.trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bekannte Whisper-Halluzinationen (deutsch), menschenlesbar. Vergleich
    /// erfolgt normalisiert (klein, ohne Satz-/Sonderzeichen). Zum Nachjustieren
    /// einfach Einträge ergänzen oder entfernen.
    private static let hallucinationPhrases: [String] = [
        // Höflichkeitsfloskeln
        "Vielen Dank",
        "Vielen Dank fürs Zuschauen",
        "Vielen Dank fürs Zuhören",
        "Danke fürs Zuschauen",
        "Danke fürs Zuhören",
        "Danke schön",
        "Dankeschön",
        "Bis zum nächsten Mal",
        "Bis zum nächsten Video",
        "Tschüss",
        // Untertitel-Credits (rein maschinell — praktisch immer Halluzination)
        "Untertitel",
        "Untertitel von",
        "Untertitelung",
        "Untertitelung des ZDF für funk",
        "Untertitel im Auftrag des ZDF",
        "Untertitel der Amara.org-Community",
        "Amara.org",
        "Copyright WDR",
    ]

    private static let normalizedHallucinations: Set<String> =
        Set(hallucinationPhrases.map(normalize))

    /// Zerlegt den Text in (Kopf, letzter Satz). Der letzte Satz ist der Text
    /// nach dem letzten Satzende (`. ! ? …` oder Zeilenumbruch); der Kopf ist
    /// alles davor inklusive dieses Satzendes. Gibt es kein Satzende, ist der
    /// gesamte Text der "letzte Satz" und der Kopf leer.
    private static func splitLastSentence(_ text: String) -> (head: String, tail: String) {
        let terminators: Set<Character> = [".", "!", "?", "\u{2026}"]
        let closingQuotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{00BB}", "\u{2019}"]

        guard !text.isEmpty else { return ("", "") }

        // Ende des inhaltlichen Teils: abschließende Satzzeichen, Anführungs-
        // zeichen und Leerraum überspringen.
        var contentEnd = text.endIndex
        while contentEnd > text.startIndex {
            let before = text.index(before: contentEnd)
            let c = text[before]
            if terminators.contains(c) || closingQuotes.contains(c) || c == " " || c.isNewline {
                contentEnd = before
            } else {
                break
            }
        }

        // Vom Inhaltsende rückwärts bis zum vorherigen Satzende laufen.
        var scan = contentEnd
        var boundary: String.Index? = nil
        while scan > text.startIndex {
            let before = text.index(before: scan)
            let c = text[before]
            if terminators.contains(c) || c.isNewline {
                boundary = before
                break
            }
            scan = before
        }

        if let boundary {
            let afterBoundary = text.index(after: boundary)
            let head = String(text[..<afterBoundary])
            let tail = String(text[afterBoundary..<contentEnd])
            return (head, tail)
        } else {
            return ("", String(text[..<contentEnd]))
        }
    }

    /// Klein, nur Buchstaben und einfache Leerzeichen — für toleranten Vergleich.
    private static func normalize(_ text: String) -> String {
        let filtered = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(filtered)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }
}
