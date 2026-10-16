import Foundation

// MARK: - Transcript History

/// Woher ein Verlaufseintrag stammt, wenn er aus einer Sprachnachricht
/// (Audiodatei, z. B. iPhone-Memo) kommt. Damit führt ein Tippen in
/// „Zuletzt“ zurück ins Ergebnisfenster statt nur zu kopieren.
public struct VoiceMessageReference: Codable, Equatable, Sendable {
    public let fileName: String
    /// Pfad der Originaldatei — für „Als .txt“ neben dem Original. Kann
    /// inzwischen verschoben oder gelöscht sein.
    public let sourcePath: String

    public init(fileName: String, sourcePath: String) {
        self.fileName = fileName
        self.sourcePath = sourcePath
    }
}

/// Was ein Tippen auf einen Eintrag in „Zuletzt“ auslöst.
public enum HistoryEntryAction: Equatable, Sendable {
    /// Text zurück in die Zwischenablage (Rettung bei falschem Feld).
    case copyText
    /// Das Sprachnachricht-Fenster mit dem Transkript wieder öffnen.
    case openVoiceMessage
}

/// Ein aufbewahrtes Ergebnis, damit ein in das falsche Feld getippter Text
/// nicht verloren geht. Bleibt rein lokal auf dem Gerät.
///
/// Liegt in `BlitztextCore`, damit Einfügen, Limit und das Laden alter
/// Verlaufsdateien ohne Xcode testbar sind.
public struct TranscriptHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let type: WorkflowType
    public let date: Date
    /// Gesetzt, wenn der Eintrag aus einer Sprachnachricht stammt. Fehlt in
    /// Verlaufsdateien älterer Versionen — dann ist es ein Diktat.
    public let voiceMessage: VoiceMessageReference?

    public init(
        id: UUID = UUID(),
        text: String,
        type: WorkflowType,
        date: Date,
        voiceMessage: VoiceMessageReference? = nil
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.date = date
        self.voiceMessage = voiceMessage
    }

    public var tapAction: HistoryEntryAction {
        voiceMessage == nil ? .copyText : .openVoiceMessage
    }
}

public enum TranscriptHistory {
    /// Legt einen Eintrag oben in den Verlauf und hält das Limit ein.
    /// Ein Diktat mit demselben Text wie der oberste Eintrag wird
    /// zusammengefasst — eine Sprachnachricht nie, sonst wäre ihr Fenster
    /// über „Zuletzt“ nicht mehr erreichbar.
    public static func inserting(
        _ entry: TranscriptHistoryEntry,
        into history: [TranscriptHistoryEntry],
        limit: Int
    ) -> [TranscriptHistoryEntry] {
        guard limit > 0 else { return [] }
        if let first = history.first,
           first.text == entry.text,
           first.voiceMessage == entry.voiceMessage {
            return Array(history.prefix(limit))
        }
        return Array(([entry] + history).prefix(limit))
    }
}
