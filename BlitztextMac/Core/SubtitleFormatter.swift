import Foundation

/// Ein Untertitel-Eintrag: Zeitbereich + Text.
public struct SubtitleCue: Equatable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Erzeugt Untertitel-Dateien aus Timestamp-Segmenten. Reine, testbare Logik.
public enum SubtitleFormatter {
    /// Entfernt WhisperKit-Spezial-Tokens wie `<|de|>` oder `<|3.68|>` aus dem Text.
    public static func strippingTokens(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zeitstempel im SRT-Format `HH:MM:SS,mmm` (Millisekunden mit Komma).
    public static func srtTimecode(_ seconds: Double) -> String {
        let totalMs = max(0, Int((seconds * 1000).rounded()))
        let ms = totalMs % 1000
        let s = (totalMs / 1000) % 60
        let m = (totalMs / 60_000) % 60
        let h = totalMs / 3_600_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// Vollständiges SubRip-(.srt)-Dokument aus den Cues.
    public static func srt(from cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(srtTimecode(cue.start)) --> \(srtTimecode(cue.end))\n\(cue.text)\n"
        }
        .joined(separator: "\n")
    }
}
